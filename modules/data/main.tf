###############################################################################
# Data services module
#
# Provides:
#   - Azure SQL Server + Database
#   - Storage account #1 (Blob storage with a container)
#   - Storage account #2 (general-purpose Storage Account)
###############################################################################

# Storage account names must be globally unique, 3-24 lowercase alphanumeric chars.
# Use random_string to suffix the prefix-derived name.
resource "random_string" "sa_suffix" {
  length    = 6
  special   = false
  upper     = false
  numeric   = true
  min_lower = 2
}

###############################################################################
# Azure SQL - public access disabled, reachable only via Private Endpoint.
###############################################################################
resource "azurerm_mssql_server" "this" {
  name                          = "${var.prefix}-sql-${random_string.sa_suffix.result}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "12.0"
  administrator_login           = var.sql_admin_username
  administrator_login_password  = var.sql_admin_password
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false
  tags                          = var.tags
}

resource "azurerm_mssql_database" "this" {
  name           = "${var.prefix}-appdb"
  server_id      = azurerm_mssql_server.this.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  max_size_gb    = 32
  sku_name       = var.sql_database_sku
  zone_redundant = var.sql_zone_redundant
  ledger_enabled = true
  tags           = var.tags
}

# Auditing: send extended auditing events to Log Analytics.
resource "azurerm_mssql_server_extended_auditing_policy" "this" {
  server_id              = azurerm_mssql_server.this.id
  log_monitoring_enabled = true
  retention_in_days      = 90
  enabled                = true
}

###############################################################################
# Private DNS zone + Private Endpoint for Azure SQL
###############################################################################
resource "azurerm_private_dns_zone" "sql" {
  name                = "privatelink.database.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql" {
  name                  = "${var.prefix}-sql-dnslink"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.sql.name
  virtual_network_id    = var.spoke_vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "sql" {
  name                = "${var.prefix}-sql-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.prefix}-sql-psc"
    private_connection_resource_id = azurerm_mssql_server.this.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }

  private_dns_zone_group {
    name                 = "sql-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql.id]
  }
}

###############################################################################
# Storage account #1 - "Blob Storage" (locked down)
###############################################################################
resource "azurerm_storage_account" "blob" {
  name                            = "${var.prefix}blob${random_string.sa_suffix.result}"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = var.storage_replication_type
  account_kind                    = "StorageV2"
  access_tier                     = "Hot"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = var.blob_public_network_access_enabled
  shared_access_key_enabled       = true
  tags                            = var.tags

  network_rules {
    default_action             = var.blob_public_network_access_enabled ? "Allow" : "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }
}

resource "azurerm_storage_container" "app" {
  name                  = "app-data"
  storage_account_name  = azurerm_storage_account.blob.name
  container_access_type = "private"
}

###############################################################################
# Storage account #2 - generic Storage Account (locked down)
###############################################################################
resource "azurerm_storage_account" "general" {
  name                            = "${var.prefix}gen${random_string.sa_suffix.result}"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = var.storage_replication_type
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false
  shared_access_key_enabled       = true
  tags                            = var.tags

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  queue_properties {
    logging {
      delete                = true
      read                  = true
      write                 = true
      version               = "1.0"
      retention_policy_days = 10
    }
  }
}

###############################################################################
# Diagnostic settings for SQL Database and Storage
###############################################################################
resource "azurerm_monitor_diagnostic_setting" "sql_db" {
  name                       = "${var.prefix}-sqldb-diag"
  target_resource_id         = azurerm_mssql_database.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "audit"
  }

  metric {
    category = "AllMetrics"
  }
}

###############################################################################
# Optional resource locks (CanNotDelete) on stateful resources
###############################################################################
locals {
  lock_targets = var.enable_resource_locks ? {
    sql_server   = azurerm_mssql_server.this.id
    sql_database = azurerm_mssql_database.this.id
    blob_sa      = azurerm_storage_account.blob.id
    general_sa   = azurerm_storage_account.general.id
  } : {}
}

resource "azurerm_management_lock" "stateful" {
  for_each   = local.lock_targets
  name       = "${var.prefix}-${each.key}-lock"
  scope      = each.value
  lock_level = "CanNotDelete"
  notes      = "Terraform-managed deletion guard."
}
