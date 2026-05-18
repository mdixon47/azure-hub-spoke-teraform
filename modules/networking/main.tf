###############################################################################
# Networking module
#
# Provides:
#   - Hub VNet  (Bastion, Firewall, Application Gateway subnets)
#   - Spoke VNet (Web Tier, App Tier subnets)
#   - Bidirectional VNet peering between hub and spoke
###############################################################################

locals {
  hub_name   = "${var.prefix}-hub-vnet"
  spoke_name = "${var.prefix}-spoke-vnet"
}

###############################################################################
# Hub VNet
###############################################################################
resource "azurerm_virtual_network" "hub" {
  name                = local.hub_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.hub_vnet_cidr]
  tags                = var.tags
}

# AzureBastionSubnet name is mandatory and must be exactly "AzureBastionSubnet".
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_vnet_cidr, 10, 0)] # /26 from a /16
}

# AzureFirewallSubnet name is mandatory and must be exactly "AzureFirewallSubnet".
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_vnet_cidr, 10, 1)] # /26
}

resource "azurerm_subnet" "appgw" {
  name                 = "appgw-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_vnet_cidr, 8, 1)] # /24
}

# Dedicated subnet for Private Endpoints (SQL, Storage, etc.).
resource "azurerm_subnet" "private_endpoints" {
  name                 = "pe-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [cidrsubnet(var.spoke_vnet_cidr, 8, 10)] # /24
}

###############################################################################
# Spoke VNet
###############################################################################
resource "azurerm_virtual_network" "spoke" {
  name                = local.spoke_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.spoke_vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "web" {
  name                 = "web-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [cidrsubnet(var.spoke_vnet_cidr, 8, 1)] # /24

  service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
}

resource "azurerm_subnet" "app" {
  name                 = "app-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [cidrsubnet(var.spoke_vnet_cidr, 8, 2)] # /24

  service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
}

###############################################################################
# VNet Peering (bidirectional)
###############################################################################
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "${local.hub_name}-to-${local.spoke_name}"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "${local.spoke_name}-to-${local.hub_name}"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
