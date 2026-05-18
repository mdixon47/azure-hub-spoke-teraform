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

variable "web_subnet_id" {
  description = "Subnet ID for the web tier VM."
  type        = string
}

variable "app_subnet_id" {
  description = "Subnet ID for the app tier VM."
  type        = string
}

variable "web_subnet_cidr" {
  description = "Web subnet CIDR (used by NSG rules)."
  type        = string
}

variable "app_subnet_cidr" {
  description = "App subnet CIDR (used by NSG rules)."
  type        = string
}

variable "bastion_subnet_cidr" {
  description = "AzureBastionSubnet CIDR (allowed source for SSH management)."
  type        = string
}

variable "appgw_subnet_cidr" {
  description = "Application Gateway subnet CIDR (allowed source for HTTP/HTTPS to web tier)."
  type        = string
}

variable "vm_admin_username" {
  description = "Linux admin username."
  type        = string
}

variable "vm_admin_password" {
  description = "Linux admin password. Required only when vm_admin_ssh_public_key is empty."
  type        = string
  sensitive   = true
  default     = null
}

variable "vm_admin_ssh_public_key" {
  description = "SSH public key for the Linux admin user. When provided, password auth is disabled."
  type        = string
  default     = ""
}

variable "web_vm_size" {
  description = "Web VM SKU."
  type        = string
  default     = "Standard_B2s"
}

variable "app_vm_size" {
  description = "App VM SKU."
  type        = string
  default     = "Standard_B2s"
}

variable "allow_vm_extensions" {
  description = "Whether to allow VM extension operations. Disable (CKV_AZURE_50) unless agents (Monitor, AAD login, etc.) are needed."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
