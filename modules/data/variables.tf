variable "prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group."
  type        = string
}

variable "sql_admin_username" {
  description = "Azure SQL administrator login."
  type        = string
}

variable "sql_admin_password" {
  description = "Azure SQL administrator password."
  type        = string
  sensitive   = true
}

variable "private_endpoints_subnet_id" {
  description = "Subnet ID where Private Endpoints will be deployed."
  type        = string
}

variable "spoke_vnet_id" {
  description = "Spoke VNet ID for private DNS zone linking."
  type        = string
}

variable "allowed_subnet_ids" {
  description = "Subnet IDs allowed to reach storage accounts via service endpoints."
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostic settings."
  type        = string
}

variable "enable_resource_locks" {
  description = "When true, applies lifecycle prevent_destroy to stateful resources."
  type        = bool
  default     = false
}

variable "sql_database_sku" {
  description = "SKU for the Azure SQL database. Zone redundancy requires a Premium/Business Critical or General Purpose Gen5+ tier."
  type        = string
  default     = "S0"
}

variable "sql_zone_redundant" {
  description = "Enable zone redundancy for the Azure SQL database. Only supported on Premium/Business Critical and General Purpose Gen5+ tiers."
  type        = bool
  default     = false
}

variable "storage_replication_type" {
  description = "Replication strategy for storage accounts. GZRS combines zone + region redundancy and satisfies CKV_AZURE_206."
  type        = string
  default     = "GZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "storage_replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "blob_public_network_access_enabled" {
  description = "When true, opens the blob Storage Account public endpoint and sets its default firewall action to Allow so Terraform can create containers from a hosted CI runner. Use only in dev; production should keep this false and bootstrap via Private Endpoint or a JIT firewall punch."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
