variable "prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that owns the networking resources."
  type        = string
}

variable "hub_vnet_cidr" {
  description = "CIDR for the hub VNet."
  type        = string
}

variable "spoke_vnet_cidr" {
  description = "CIDR for the spoke VNet."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
