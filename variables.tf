###############################################################################
# Root-level input variables
###############################################################################

variable "prefix" {
  description = "Short name used to prefix all resources (3-8 lowercase alphanumeric chars)."
  type        = string
  default     = "hubspk"

  validation {
    condition     = can(regex("^[a-z0-9]{3,8}$", var.prefix))
    error_message = "Prefix must be 3-8 lowercase alphanumeric characters."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    environment = "dev"
    project     = "hub-spoke-reference"
    managed_by  = "terraform"
  }
}

# ----------------------------------------------------------------------------
# Networking address spaces
# ----------------------------------------------------------------------------

variable "hub_vnet_cidr" {
  description = "Address space of the hub VNet."
  type        = string
  default     = "10.0.0.0/16"
}

variable "spoke_vnet_cidr" {
  description = "Address space of the spoke VNet."
  type        = string
  default     = "10.1.0.0/16"
}

# ----------------------------------------------------------------------------
# Credentials (sensitive)
# ----------------------------------------------------------------------------

variable "vm_admin_username" {
  description = "Admin username for the Linux VMs."
  type        = string
  default     = "azureuser"
}

variable "vm_admin_password" {
  description = "Admin password for the Linux VMs. Required when vm_admin_ssh_public_key is empty."
  type        = string
  sensitive   = true
  default     = null
}

variable "vm_admin_ssh_public_key" {
  description = "SSH public key for the Linux VMs. When set, disables password authentication."
  type        = string
  default     = ""
}

variable "sql_admin_username" {
  description = "Administrator login for the Azure SQL server."
  type        = string
  default     = "sqladminuser"
}

variable "sql_admin_password" {
  description = "Administrator password for the Azure SQL server. Provide via TF_VAR_sql_admin_password or tfvars."
  type        = string
  sensitive   = true
}

# ----------------------------------------------------------------------------
# VM sizing
# ----------------------------------------------------------------------------

variable "web_vm_size" {
  description = "VM SKU for the web-tier server."
  type        = string
  default     = "Standard_B2s"
}

variable "app_vm_size" {
  description = "VM SKU for the app-tier server."
  type        = string
  default     = "Standard_B2s"
}

# ----------------------------------------------------------------------------
# Observability & lifecycle
# ----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Log Analytics workspace retention in days."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "enable_resource_locks" {
  description = "When true, applies CanNotDelete management locks on stateful resources (SQL, Storage)."
  type        = bool
  default     = false
}

# ----------------------------------------------------------------------------
# HTTPS / Key Vault
# ----------------------------------------------------------------------------

variable "enable_https" {
  description = "When true, deploys the security module (Key Vault + UAMI + self-signed cert) and adds an HTTPS listener + HTTP->HTTPS redirect on Application Gateway."
  type        = bool
  default     = true
}

variable "appgw_cert_subject" {
  description = "Subject DN for the Application Gateway TLS certificate."
  type        = string
  default     = "CN=appgw.example.com"
}

variable "appgw_cert_dns_names" {
  description = "DNS SANs for the Application Gateway TLS certificate."
  type        = list(string)
  default     = ["appgw.example.com"]
}

variable "kv_public_network_access_enabled" {
  description = "Allow public network access to Key Vault. Required when running Terraform from outside the VNet (e.g. local CLI or hosted CI). Production deployments should set this false and front the vault with a Private Endpoint."
  type        = bool
  default     = false
}

variable "kv_allowed_ip_ranges" {
  description = "CIDR ranges allowed through the Key Vault firewall during bootstrap (typically the deployer's egress IP). Only effective when kv_public_network_access_enabled is true."
  type        = list(string)
  default     = []
}

# ----------------------------------------------------------------------------
# Storage (data module)
# ----------------------------------------------------------------------------

variable "blob_public_network_access_enabled" {
  description = "Allow public network access (and Allow default firewall action) on the blob Storage Account. Required when Terraform creates blob containers from outside the VNet (e.g. hosted CI). Production should keep this false and bootstrap containers via Private Endpoint or a JIT firewall punch."
  type        = bool
  default     = false
}
