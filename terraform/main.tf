locals {
  prefix       = var.name
  rg_name      = var.rg_name != "" ? var.rg_name : "rg-${local.prefix}-${var.environment}"
  vnet_name    = "vnet-${local.prefix}-${var.environment}"
  integration  = "snet-${local.prefix}-integration-${var.environment}"
  pe_subnet    = "snet-${local.prefix}-privatelink-${var.environment}"
  plan_name    = "plan-${local.prefix}-${var.environment}"
  logic_name   = "logic-${local.prefix}-${var.environment}"
  consumption  = "logic-con-${local.prefix}-${var.environment}"
  storage_name = substr(replace("st${var.environment}${local.prefix}", "-", ""), 0, 24)
  share_name   = "share-${local.prefix}-${var.environment}"

  tags = merge(var.tags, {
    environment = var.environment
    managedBy   = "Terraform"
  })
}

resource "azurerm_resource_group" "main" {
  name     = local.rg_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = local.tags
}

resource "azurerm_subnet" "integration" {
  name                 = local.integration
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.integration_subnet_cidrs

  delegation {
    name = "delegation-logic-apps"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = local.pe_subnet
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.private_endpoint_subnet_cidrs
}

resource "azurerm_service_plan" "main" {
  #checkov:skip=CKV_AZURE_212: Single-instance default for the template - scale via ElasticPremium / runtime_scale_monitoring in production
  #checkov:skip=CKV_AZURE_225: WS1/WS2/WS3 (Logic Apps Standard) SKUs do not support zone redundancy
  name                = local.plan_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Windows"
  sku_name            = var.service_plan_sku
  tags                = local.tags
}

resource "azurerm_storage_account" "main" {
  #checkov:skip=CKV_AZURE_206: LRS is the default for the template - set storage_replication_type = "ZRS" for production workloads
  #checkov:skip=CKV_AZURE_33: Queue logging is configured via azurerm_storage_account_queue_properties.main (dedicated resource, replaces the deprecated queue_properties block)
  #checkov:skip=CKV2_AZURE_40: Logic App Standard requires Shared Key access (storage_account_access_key) for the content share; runtime data-plane access uses Managed Identity
  #checkov:skip=CKV2_AZURE_41: Data-plane access uses Managed Identity, no SAS token workflows; sas_policy is set defensively
  #checkov:skip=CKV2_AZURE_1: Customer-Managed Key encryption requires an extra Key Vault - out of scope for the base template (platform SSE is enabled by default)
  name                            = local.storage_name
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = var.storage_replication_type
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  share_properties {
    retention_policy {
      days = 7
    }
  }

  sas_policy {
    expiration_period = "90.00:00:00"
    expiration_action = "Log"
  }

  tags = local.tags
}

resource "azurerm_storage_account_queue_properties" "main" {
  storage_account_id = azurerm_storage_account.main.id

  logging {
    version = "1.0"
    delete  = true
    read    = true
    write   = true
  }
}

resource "azurerm_storage_share" "main" {
  name                 = local.share_name
  storage_account_name = azurerm_storage_account.main.name
  quota                = 10
}

locals {
  private_dns_zones = {
    blob  = "privatelink.blob.core.windows.net"
    file  = "privatelink.file.core.windows.net"
    queue = "privatelink.queue.core.windows.net"
    table = "privatelink.table.core.windows.net"
    sites = "privatelink.azurewebsites.net"
  }

  storage_subresources = ["blob", "file", "queue", "table"]
}

resource "azurerm_private_dns_zone" "main" {
  for_each            = local.private_dns_zones
  name                = each.value
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "main" {
  for_each              = local.private_dns_zones
  name                  = "link-${azurerm_virtual_network.main.name}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.main[each.key].name
  virtual_network_id    = azurerm_virtual_network.main.id
}

# Private Endpoint per Storage subresource. A Logic App Standard is a function
# host underneath: it needs blob, file, queue AND table privately reachable.
# Skipping queue/table leaves DNS resolving to public IPs while the account is
# public-network-locked → the host fails to boot with HTTP 403 Forbidden.
resource "azurerm_private_endpoint" "storage" {
  for_each            = toset(local.storage_subresources)
  name                = "pe-${local.storage_name}-${each.key}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-${local.storage_name}-${each.key}"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = [each.key]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-${each.key}"
    private_dns_zone_ids = [azurerm_private_dns_zone.main[each.key].id]
  }

  tags = local.tags
}

# The Logic App itself — its *.azurewebsites.net hostname is also reachable
# only via a private endpoint when public_network_access is disabled.
resource "azurerm_private_endpoint" "sites" {
  name                = "pe-${local.logic_name}-sites"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-${local.logic_name}-sites"
    private_connection_resource_id = azurerm_logic_app_standard.main.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-sites"
    private_dns_zone_ids = [azurerm_private_dns_zone.main["sites"].id]
  }

  depends_on = [azurerm_logic_app_standard.main]
  tags       = local.tags
}

# Minimal host.json/connections.json bootstrap: a fresh Standard Logic App
# boots the workflow host with an empty file share, which the portal designer
# and the runtime both trip over. Uploading an empty definition avoids it.
resource "local_file" "host_json" {
  count    = var.bootstrap_content ? 1 : 0
  filename = "${path.module}/.bootstrap-content/host.json"
  content = jsonencode({
    version = "2.0"
    extensionBundle = {
      id      = "Microsoft.Azure.Functions.ExtensionBundle.Workflows"
      version = "[1.*, 2.0.0)"
    }
  })
}

resource "local_file" "connections_json" {
  count    = var.bootstrap_content ? 1 : 0
  filename = "${path.module}/.bootstrap-content/connections.json"
  content = jsonencode({
    managedApiConnections      = {}
    serviceProviderConnections = {}
  })
}

resource "azurerm_storage_share_directory" "wwwroot" {
  count            = var.bootstrap_content ? 1 : 0
  name             = "site/wwwroot"
  storage_share_id = azurerm_storage_share.main.id
  depends_on       = [azurerm_logic_app_standard.main]
}

resource "azurerm_storage_share_file" "host_json" {
  count            = var.bootstrap_content ? 1 : 0
  name             = "host.json"
  storage_share_id = azurerm_storage_share.main.id
  path             = azurerm_storage_share_directory.wwwroot[0].name
  source           = local_file.host_json[0].filename
  content_type     = "application/json"

  lifecycle {
    ignore_changes = [source, content_type]
  }
}

resource "azurerm_storage_share_file" "connections_json" {
  count            = var.bootstrap_content ? 1 : 0
  name             = "connections.json"
  storage_share_id = azurerm_storage_share.main.id
  path             = azurerm_storage_share_directory.wwwroot[0].name
  source           = local_file.connections_json[0].filename
  content_type     = "application/json"

  lifecycle {
    ignore_changes = [source, content_type]
  }

  depends_on = [azurerm_storage_share_file.host_json]
}

resource "azurerm_logic_app_standard" "main" {
  name                       = local.logic_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  app_service_plan_id        = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  storage_account_share_name = azurerm_storage_share.main.name
  https_only                 = true
  client_affinity_enabled    = false
  enabled                    = true
  public_network_access      = "Disabled"
  virtual_network_subnet_id  = azurerm_subnet.integration.id
  tags                       = local.tags

  app_settings = merge(
    {
      "WEBSITE_CONTENTOVERVNET" = "1"
      "WEBSITE_VNET_ROUTE_ALL"  = "1"
    },
    var.app_settings
  )

  site_config {
    always_on              = true
    http2_enabled          = true
    min_tls_version        = "1.2"
    ftps_state             = "Disabled"
    vnet_route_all_enabled = true
  }

  dynamic "identity" {
    for_each = var.identity != null ? [var.identity] : []
    content {
      type         = identity.value.type
      identity_ids = lookup(identity.value, "identity_ids", null)
    }
  }

  # The host must not boot before its private Storage endpoints exist,
  # otherwise the first scale-up races the network config and fails.
  depends_on = [
    azurerm_private_endpoint.storage["blob"],
    azurerm_private_endpoint.storage["file"],
    azurerm_private_endpoint.storage["queue"],
    azurerm_private_endpoint.storage["table"],
  ]
}

# Keyless data-plane access for the System-Assigned identity once the host is
# up — queue/table/blob are reachable over the private endpoints and accessed
# without any storage keys.
resource "azurerm_role_assignment" "storage_data_roles" {
  for_each = toset([
    "Storage Blob Data Owner",
    "Storage Queue Data Contributor",
    "Storage Table Data Contributor",
  ])

  scope                = azurerm_storage_account.main.id
  role_definition_name = each.key
  principal_id         = azurerm_logic_app_standard.main.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_logic_app_workflow" "consumption" {
  count               = var.create_consumption_workflow ? 1 : 0
  name                = local.consumption
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  enabled             = true
  tags                = local.tags

  workflow_parameters = {
    "$connections" = jsonencode({ type = "Object" })
  }

  parameters = {
    "$connections" = jsonencode({})
  }

  identity {
    type = "SystemAssigned"
  }

  dynamic "access_control" {
    for_each = var.consumption_trigger_ip_ranges != null ? [1] : []
    content {
      trigger {
        allowed_caller_ip_address_range = var.consumption_trigger_ip_ranges
      }
    }
  }
}
