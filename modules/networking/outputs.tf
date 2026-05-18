output "hub_vnet_id" {
  value       = azurerm_virtual_network.hub.id
  description = "ID of the hub VNet."
}

output "spoke_vnet_id" {
  value       = azurerm_virtual_network.spoke.id
  description = "ID of the spoke VNet."
}

output "bastion_subnet_id" {
  value       = azurerm_subnet.bastion.id
  description = "AzureBastionSubnet ID."
}

output "firewall_subnet_id" {
  value       = azurerm_subnet.firewall.id
  description = "AzureFirewallSubnet ID."
}

output "appgw_subnet_id" {
  value       = azurerm_subnet.appgw.id
  description = "Application Gateway subnet ID."
}

output "web_subnet_id" {
  value       = azurerm_subnet.web.id
  description = "Web tier subnet ID."
}

output "app_subnet_id" {
  value       = azurerm_subnet.app.id
  description = "App tier subnet ID."
}

output "bastion_subnet_cidr" {
  value       = azurerm_subnet.bastion.address_prefixes[0]
  description = "AzureBastionSubnet CIDR (used by NSG rules)."
}

output "appgw_subnet_cidr" {
  value       = azurerm_subnet.appgw.address_prefixes[0]
  description = "Application Gateway subnet CIDR (used by NSG rules)."
}

output "web_subnet_cidr" {
  value       = azurerm_subnet.web.address_prefixes[0]
  description = "Web subnet CIDR."
}

output "app_subnet_cidr" {
  value       = azurerm_subnet.app.address_prefixes[0]
  description = "App subnet CIDR."
}

output "private_endpoints_subnet_id" {
  value       = azurerm_subnet.private_endpoints.id
  description = "Private Endpoints subnet ID (spoke)."
}
