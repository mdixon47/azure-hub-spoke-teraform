output "sql_server_id" {
  value       = azurerm_mssql_server.this.id
  description = "Azure SQL server ID."
}

output "sql_server_fqdn" {
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
  description = "Azure SQL server FQDN."
}

output "sql_database_id" {
  value       = azurerm_mssql_database.this.id
  description = "Azure SQL database ID."
}

output "blob_storage_account_id" {
  value       = azurerm_storage_account.blob.id
  description = "ID of the blob storage account."
}

output "blob_storage_account_name" {
  value       = azurerm_storage_account.blob.name
  description = "Name of the blob storage account."
}

output "blob_storage_primary_endpoint" {
  value       = azurerm_storage_account.blob.primary_blob_endpoint
  description = "Primary blob endpoint."
}

output "blob_container_name" {
  value       = azurerm_storage_container.app.name
  description = "Application blob container name."
}

output "general_storage_account_id" {
  value       = azurerm_storage_account.general.id
  description = "ID of the general-purpose storage account."
}

output "general_storage_account_name" {
  value       = azurerm_storage_account.general.name
  description = "Name of the general-purpose storage account."
}
