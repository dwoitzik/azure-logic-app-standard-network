output "resource_group_id" {
  description = "Resource ID of the Resource Group."
  value       = azurerm_resource_group.main.id
}

output "resource_group_name" {
  description = "Name of the Resource Group."
  value       = azurerm_resource_group.main.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic App Standard."
  value       = azurerm_logic_app_standard.main.id
}

output "logic_app_name" {
  description = "Name of the Logic App Standard."
  value       = azurerm_logic_app_standard.main.name
}

output "default_hostname" {
  description = "Default hostname of the Logic App Standard (resolves privately via the sites Private Endpoint)."
  value       = azurerm_logic_app_standard.main.default_hostname
}

output "principal_id" {
  description = "Principal ID of the Logic App Standard's Managed Identity."
  value       = azurerm_logic_app_standard.main.identity[0].principal_id
}

output "outbound_ip_addresses" {
  description = "Possible outbound IP addresses of the Logic App Standard."
  value       = azurerm_logic_app_standard.main.possible_outbound_ip_addresses
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan."
  value       = azurerm_service_plan.main.id
}

output "storage_account_id" {
  description = "Resource ID of the Storage Account (for Private Endpoint configuration)."
  value       = azurerm_storage_account.main.id
}

output "storage_account_name" {
  description = "Name of the Storage Account backing the Logic App Standard."
  value       = azurerm_storage_account.main.name
}

output "storage_account_share_name" {
  description = "Name of the file share holding the workflow content."
  value       = azurerm_storage_share.main.name
}

output "private_endpoint_ids" {
  description = "IDs of all Private Endpoints (storage blob/file/queue/table + sites)."
  value = {
    blob  = azurerm_private_endpoint.storage["blob"].id
    file  = azurerm_private_endpoint.storage["file"].id
    queue = azurerm_private_endpoint.storage["queue"].id
    table = azurerm_private_endpoint.storage["table"].id
    sites = azurerm_private_endpoint.sites.id
  }
}

output "consumption_workflow_id" {
  description = "Resource ID of the optional Consumption workflow."
  value       = var.create_consumption_workflow ? azurerm_logic_app_workflow.consumption[0].id : null
}

output "consumption_workflow_endpoint" {
  description = "Trigger endpoint of the optional Consumption workflow."
  value       = var.create_consumption_workflow ? azurerm_logic_app_workflow.consumption[0].access_endpoint : null
  sensitive   = true
}
