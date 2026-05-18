output "web_vm_id" {
  value       = azurerm_linux_virtual_machine.web.id
  description = "Web tier VM ID."
}

output "app_vm_id" {
  value       = azurerm_linux_virtual_machine.app.id
  description = "App tier VM ID."
}

output "web_vm_private_ip" {
  value       = azurerm_network_interface.web.private_ip_address
  description = "Private IP of the web tier VM (used by Application Gateway backend pool)."
}

output "app_vm_private_ip" {
  value       = azurerm_network_interface.app.private_ip_address
  description = "Private IP of the app tier VM."
}

output "web_nsg_id" {
  value       = azurerm_network_security_group.web.id
  description = "Web NSG ID."
}

output "app_nsg_id" {
  value       = azurerm_network_security_group.app.id
  description = "App NSG ID."
}
