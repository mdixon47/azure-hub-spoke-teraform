output "resource_group_name" {
  description = "Name of the resource group."
  value       = azurerm_resource_group.this.name
}

output "application_gateway_public_ip" {
  description = "Public IP of the Application Gateway (entry point for user traffic)."
  value       = module.hub.application_gateway_public_ip
}

output "firewall_public_ip" {
  description = "Public IP of the Azure Firewall."
  value       = module.hub.firewall_public_ip
}

output "bastion_dns_name" {
  description = "DNS name of the Azure Bastion host."
  value       = module.hub.bastion_dns_name
}

output "web_vm_private_ip" {
  description = "Private IP of the Web tier VM."
  value       = module.spoke_compute.web_vm_private_ip
}

output "app_vm_private_ip" {
  description = "Private IP of the App tier VM."
  value       = module.spoke_compute.app_vm_private_ip
}

output "sql_server_fqdn" {
  description = "FQDN of the Azure SQL server."
  value       = module.data.sql_server_fqdn
}

output "blob_storage_account_name" {
  description = "Name of the storage account hosting Blob containers."
  value       = module.data.blob_storage_account_name
}

output "general_storage_account_name" {
  description = "Name of the general-purpose storage account."
  value       = module.data.general_storage_account_name
}
