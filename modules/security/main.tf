###############################################################################
# Security module
#
# Provides:
#   - User-Assigned Managed Identity used by Application Gateway to fetch the
#     TLS certificate from Key Vault.
#   - Key Vault with soft-delete + purge-protection enabled.
#   - Access policies for the Terraform deployer (cert provisioning) and the
#     Application Gateway managed identity (read-only Get).
#   - Self-signed TLS certificate stored in Key Vault and consumed by AppGw.
#
# Notes:
#   * Public network access remains enabled so the deployer can bootstrap the
#     cert. Production deployments should add a Key Vault Private Endpoint and
#     restrict `network_acls.default_action` to "Deny".
#   * Self-signed certs are appropriate for reference / dev use only. Replace
#     with a CA-issued cert (or Key Vault-managed issuer) for production.
###############################################################################

data "azurerm_client_config" "current" {}

# Key Vault names must be globally unique, 3-24 alphanumerics + hyphens.
resource "random_string" "kv_suffix" {
  length    = 6
  special   = false
  upper     = false
  numeric   = true
  min_lower = 2
}

resource "azurerm_user_assigned_identity" "appgw" {
  name                = "${var.prefix}-appgw-uami"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_key_vault" "this" {
  name                = "${var.prefix}-kv-${random_string.kv_suffix.result}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  enabled_for_disk_encryption     = false
  enabled_for_deployment          = false
  enabled_for_template_deployment = false
  enable_rbac_authorization       = false

  soft_delete_retention_days    = var.soft_delete_retention_days
  purge_protection_enabled      = true
  public_network_access_enabled = var.public_network_access_enabled

  # Default-deny firewall. Trusted Azure services (Application Gateway managed
  # identity) bypass the ACL; explicit deployer IPs may be added via
  # var.allowed_ip_ranges for bootstrap from outside Azure.
  network_acls {
    default_action = var.network_default_action
    bypass         = "AzureServices"
    ip_rules       = var.allowed_ip_ranges
  }

  tags = var.tags
}

# Deployer access policy: required to create / read the self-signed certificate.
resource "azurerm_key_vault_access_policy" "deployer" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Import", "Purge", "Recover",
  ]
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Purge", "Recover",
  ]
  key_permissions = [
    "Get", "List", "Create", "Delete", "Purge", "Recover",
  ]
}

# Application Gateway managed identity: Get-only on certs + secrets.
resource "azurerm_key_vault_access_policy" "appgw" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.appgw.principal_id

  certificate_permissions = ["Get"]
  secret_permissions      = ["Get"]
}

resource "azurerm_key_vault_certificate" "appgw" {
  name         = "${var.prefix}-appgw-cert"
  key_vault_id = azurerm_key_vault.this.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      subject            = var.cert_subject
      validity_in_months = 12
      key_usage = [
        "digitalSignature",
        "keyEncipherment",
      ]
      extended_key_usage = [
        "1.3.6.1.5.5.7.3.1", # serverAuth
      ]

      subject_alternative_names {
        dns_names = var.cert_dns_names
      }
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }
      trigger {
        days_before_expiry = 30
      }
    }
  }

  depends_on = [azurerm_key_vault_access_policy.deployer]
}
