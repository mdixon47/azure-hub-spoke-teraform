output "bastion_id" {
  value       = azurerm_bastion_host.this.id
  description = "Azure Bastion resource ID."
}

output "bastion_dns_name" {
  value       = azurerm_bastion_host.this.dns_name
  description = "Azure Bastion DNS name."
}

output "firewall_id" {
  value       = azurerm_firewall.this.id
  description = "Azure Firewall resource ID."
}

output "firewall_public_ip" {
  value       = azurerm_public_ip.firewall.ip_address
  description = "Public IP address of the Azure Firewall."
}

output "firewall_private_ip" {
  value       = azurerm_firewall.this.ip_configuration[0].private_ip_address
  description = "Private IP of the Azure Firewall (use for UDR next-hop)."
}

output "application_gateway_id" {
  value       = azurerm_application_gateway.this.id
  description = "Application Gateway resource ID."
}

output "application_gateway_public_ip" {
  value       = azurerm_public_ip.appgw.ip_address
  description = "Public IP address of the Application Gateway."
}

output "log_analytics_workspace_id" {
  value       = azurerm_log_analytics_workspace.this.id
  description = "Log Analytics workspace ID used as the diagnostics sink."
}

output "route_table_id" {
  value       = azurerm_route_table.spoke_egress.id
  description = "Spoke egress route table ID (next-hop = firewall private IP)."
}
