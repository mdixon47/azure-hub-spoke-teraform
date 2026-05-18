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

variable "cert_subject" {
  description = "Subject DN for the self-signed TLS certificate served by Application Gateway."
  type        = string
  default     = "CN=appgw.example.com"
}

variable "cert_dns_names" {
  description = "DNS SANs for the self-signed TLS certificate."
  type        = list(string)
  default     = ["appgw.example.com"]
}

variable "soft_delete_retention_days" {
  description = "Key Vault soft-delete retention window in days."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "public_network_access_enabled" {
  description = "When true, Key Vault accepts requests from public networks subject to network_acls. Set false in production and front the vault with a Private Endpoint."
  type        = bool
  default     = false
}

variable "network_default_action" {
  description = "Default action of the Key Vault firewall (network_acls.default_action). 'Deny' is required for CKV_AZURE_109 / AZU-0013."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_default_action)
    error_message = "network_default_action must be 'Allow' or 'Deny'."
  }
}

variable "allowed_ip_ranges" {
  description = "CIDR ranges allowed to reach the Key Vault data plane (e.g. the deployer's egress IP). Only honoured when public_network_access_enabled is true."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
