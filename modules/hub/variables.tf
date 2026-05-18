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

variable "bastion_subnet_id" {
  description = "AzureBastionSubnet ID."
  type        = string
}

variable "firewall_subnet_id" {
  description = "AzureFirewallSubnet ID."
  type        = string
}

variable "appgw_subnet_id" {
  description = "Application Gateway subnet ID."
  type        = string
}

variable "web_backend_ip" {
  description = "Private IP of the web tier VM (used as Application Gateway backend pool target)."
  type        = string
}

variable "spoke_subnet_associations" {
  description = "Map of static name => subnet ID for spoke subnets whose 0.0.0.0/0 traffic must be force-tunneled through the firewall. Keys must be known at plan time (do not derive from resource attributes)."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "Retention period in days for Log Analytics workspace and diagnostic settings."
  type        = number
  default     = 30
}

variable "firewall_sku_tier" {
  description = "Azure Firewall SKU tier. Premium unlocks IDPS in Deny mode (CKV_AZURE_220) and TLS inspection."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.firewall_sku_tier)
    error_message = "firewall_sku_tier must be Standard or Premium."
  }
}

variable "enable_https" {
  description = "When true, Application Gateway terminates HTTPS on a 443 listener using a cert from Key Vault and redirects HTTP traffic to HTTPS."
  type        = bool
  default     = false
}

variable "ssl_certificate_secret_id" {
  description = "Key Vault secret ID of the TLS certificate used by the HTTPS listener. Required when enable_https is true."
  type        = string
  default     = null
}

variable "user_assigned_identity_id" {
  description = "Resource ID of the User-Assigned Managed Identity used by AppGw to fetch the TLS cert. Required when enable_https is true."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
