output "key_vault_id" {
  value       = azurerm_key_vault.this.id
  description = "Key Vault resource ID."
}

output "key_vault_uri" {
  value       = azurerm_key_vault.this.vault_uri
  description = "Key Vault data-plane URI."
}

output "user_assigned_identity_id" {
  value       = azurerm_user_assigned_identity.appgw.id
  description = "User-Assigned Managed Identity ID used by Application Gateway to fetch the cert."
}

output "user_assigned_identity_principal_id" {
  value       = azurerm_user_assigned_identity.appgw.principal_id
  description = "Principal (object) ID of the Application Gateway managed identity."
}

output "ssl_certificate_secret_id" {
  value       = azurerm_key_vault_certificate.appgw.secret_id
  description = "Key Vault secret ID of the Application Gateway TLS certificate."
}

output "ssl_certificate_name" {
  value       = azurerm_key_vault_certificate.appgw.name
  description = "Name of the TLS certificate stored in Key Vault."
}
