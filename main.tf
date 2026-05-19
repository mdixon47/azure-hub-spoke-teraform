###############################################################################
# Root module - composes the hub-spoke reference architecture.
#
# Layers:
#   1. Resource group
#   2. networking      -> VNets, subnets, peering
#   3. spoke_compute   -> Web/App NSGs and Linux VMs
#   4. security        -> Key Vault + UAMI + TLS cert (optional, gated by enable_https)
#   5. hub             -> Bastion, Firewall, Application Gateway (consumes cert from security)
#   6. data            -> Azure SQL + Storage Accounts
###############################################################################

resource "azurerm_resource_group" "this" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.tags
}

module "networking" {
  source = "./modules/networking"

  prefix              = var.prefix
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  hub_vnet_cidr       = var.hub_vnet_cidr
  spoke_vnet_cidr     = var.spoke_vnet_cidr
  tags                = var.tags
}

module "spoke_compute" {
  source = "./modules/spoke-compute"

  prefix              = var.prefix
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  web_subnet_id       = module.networking.web_subnet_id
  app_subnet_id       = module.networking.app_subnet_id
  web_subnet_cidr     = module.networking.web_subnet_cidr
  app_subnet_cidr     = module.networking.app_subnet_cidr
  bastion_subnet_cidr = module.networking.bastion_subnet_cidr
  appgw_subnet_cidr   = module.networking.appgw_subnet_cidr

  vm_admin_username       = var.vm_admin_username
  vm_admin_password       = var.vm_admin_password
  vm_admin_ssh_public_key = var.vm_admin_ssh_public_key
  web_vm_size             = var.web_vm_size
  app_vm_size             = var.app_vm_size

  tags = var.tags
}

module "security" {
  count  = var.enable_https ? 1 : 0
  source = "./modules/security"

  prefix              = var.prefix
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  cert_subject   = var.appgw_cert_subject
  cert_dns_names = var.appgw_cert_dns_names

  public_network_access_enabled = var.kv_public_network_access_enabled
  allowed_ip_ranges             = var.kv_allowed_ip_ranges

  tags = var.tags
}

module "hub" {
  source = "./modules/hub"

  prefix              = var.prefix
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  bastion_subnet_id  = module.networking.bastion_subnet_id
  firewall_subnet_id = module.networking.firewall_subnet_id
  appgw_subnet_id    = module.networking.appgw_subnet_id

  web_backend_ip = module.spoke_compute.web_vm_private_ip

  spoke_subnet_associations = {
    web = module.networking.web_subnet_id
    app = module.networking.app_subnet_id
  }

  log_retention_days = var.log_retention_days

  enable_https              = var.enable_https
  ssl_certificate_secret_id = var.enable_https ? module.security[0].ssl_certificate_secret_id : null
  user_assigned_identity_id = var.enable_https ? module.security[0].user_assigned_identity_id : null

  tags = var.tags
}

module "data" {
  source = "./modules/data"

  prefix              = var.prefix
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  sql_admin_username = var.sql_admin_username
  sql_admin_password = var.sql_admin_password

  private_endpoints_subnet_id = module.networking.private_endpoints_subnet_id
  spoke_vnet_id               = module.networking.spoke_vnet_id
  allowed_subnet_ids = [
    module.networking.web_subnet_id,
    module.networking.app_subnet_id,
  ]
  log_analytics_workspace_id         = module.hub.log_analytics_workspace_id
  enable_resource_locks              = var.enable_resource_locks
  blob_public_network_access_enabled = var.blob_public_network_access_enabled

  tags = var.tags
}
