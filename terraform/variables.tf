variable "name" {
  type        = string
  description = "Base name used to build all resource names (e.g. `workflows` → `logic-workflows-dev`)."
}

variable "environment" {
  type        = string
  description = "Environment suffix (e.g. dev, tst, prd)."
  default     = "dev"
}

variable "location" {
  type        = string
  description = "Azure region for the deployment."
  default     = "westeurope"
}

variable "rg_name" {
  type        = string
  description = "Resource Group name. If empty, derived as `rg-<name>-<environment>`."
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Standard tags applied to all resources."
  default     = {}
}

variable "vnet_address_space" {
  type        = list(string)
  description = "Address space of the demo VNet."
  default     = ["10.1.0.0/16"]
}

variable "integration_subnet_cidrs" {
  type        = list(string)
  description = "CIDR(s) for the Logic App VNet-integration subnet (delegated to Microsoft.Web/serverFarms)."
  default     = ["10.1.1.0/26"]
}

variable "private_endpoint_subnet_cidrs" {
  type        = list(string)
  description = "CIDR(s) for the Private Endpoint subnet."
  default     = ["10.1.2.0/26"]
}

variable "service_plan_sku" {
  type        = string
  description = "SKU of the Windows App Service Plan for the Standard Logic App (WS1, WS2 or WS3)."
  default     = "WS1"

  validation {
    condition     = contains(["WS1", "WS2", "WS3"], var.service_plan_sku)
    error_message = "service_plan_sku must be one of WS1, WS2, WS3."
  }
}

variable "storage_replication_type" {
  type        = string
  description = "Replication strategy for the Storage Account. Use ZRS (or GRS) for production."
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "storage_replication_type must be a valid Azure storage replication type."
  }
}

variable "app_settings" {
  type        = map(string)
  description = "Additional app settings merged into the Logic App Standard (e.g. workflow-specific settings)."
  default     = {}
}

variable "identity" {
  type = object({
    type         = string
    identity_ids = optional(list(string))
  })
  description = "Managed Identity configuration for the Logic App Standard."
  default = {
    type = "SystemAssigned"
  }
}

variable "bootstrap_content" {
  type        = bool
  description = "Upload a minimal host.json/connections.json into the file share so the workflow runtime can start with an empty definition. Set to false if workflow content is deployed via your own CI/CD."
  default     = true
}

variable "create_consumption_workflow" {
  type        = bool
  description = "Additionally deploy a Consumption (serverless) Logic App workflow next to the Standard one."
  default     = false
}

variable "consumption_trigger_ip_ranges" {
  type        = list(string)
  description = "Optional caller IP ranges for the Consumption workflow HTTP trigger. Empty/null = no IP filter."
  default     = null
}
