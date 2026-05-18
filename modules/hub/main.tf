###############################################################################
# Hub module
#
# Provides:
#   - Public IPs for Bastion, Firewall and Application Gateway
#   - Azure Bastion host (management entry point)
#   - Azure Firewall + minimal firewall policy
#   - Application Gateway (v2) sitting in front of the web tier
###############################################################################

###############################################################################
# Public IPs
###############################################################################
resource "azurerm_public_ip" "bastion" {
  name                = "${var.prefix}-bastion-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_public_ip" "firewall" {
  name                = "${var.prefix}-fw-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_public_ip" "appgw" {
  name                = "${var.prefix}-appgw-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

###############################################################################
# Azure Bastion
###############################################################################
resource "azurerm_bastion_host" "this" {
  name                = "${var.prefix}-bastion"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tags                = var.tags

  ip_configuration {
    name                 = "configuration"
    subnet_id            = var.bastion_subnet_id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

###############################################################################
# Azure Firewall (+ policy)
###############################################################################
resource "azurerm_firewall_policy" "this" {
  name                     = "${var.prefix}-fw-policy"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  sku                      = var.firewall_sku_tier
  threat_intelligence_mode = "Deny"
  tags                     = var.tags

  # IDPS in Deny mode is only available on the Premium firewall tier. The block
  # is rendered conditionally so the Standard tier (default for dev) stays valid.
  dynamic "intrusion_detection" {
    for_each = var.firewall_sku_tier == "Premium" ? [1] : []
    content {
      mode = "Deny"
    }
  }
}

resource "azurerm_firewall" "this" {
  name                = "${var.prefix}-fw"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall_sku_tier
  firewall_policy_id  = azurerm_firewall_policy.this.id
  threat_intel_mode   = "Deny"
  tags                = var.tags

  ip_configuration {
    name                 = "configuration"
    subnet_id            = var.firewall_subnet_id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
}

###############################################################################
# NSG for the Application Gateway subnet
# AppGw v2 requires inbound from GatewayManager on 65200-65535.
###############################################################################
resource "azurerm_network_security_group" "appgw" {
  name                = "${var.prefix}-appgw-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "Allow-GatewayManager"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-Internet-HTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-AzureLoadBalancer"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "appgw" {
  subnet_id                 = var.appgw_subnet_id
  network_security_group_id = azurerm_network_security_group.appgw.id
}

###############################################################################
# Route Table - force-tunnel spoke egress through the firewall
###############################################################################
resource "azurerm_route_table" "spoke_egress" {
  name                = "${var.prefix}-spoke-rt"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.this.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "spoke" {
  for_each       = var.spoke_subnet_associations
  subnet_id      = each.value
  route_table_id = azurerm_route_table.spoke_egress.id
}

###############################################################################
# Log Analytics workspace (observability sink)
###############################################################################
resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.prefix}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

###############################################################################
# Application Gateway WAF policy
###############################################################################
resource "azurerm_web_application_firewall_policy" "this" {
  name                = "${var.prefix}-waf-policy"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}

###############################################################################
# Application Gateway (WAF_v2) - terminates user traffic and forwards to Web VM
###############################################################################
locals {
  appgw_name           = "${var.prefix}-appgw"
  frontend_ip_name     = "appgw-frontend-ip"
  frontend_port_80     = "appgw-port-80"
  frontend_port_443    = "appgw-port-443"
  backend_pool_name    = "web-backend-pool"
  http_setting_name    = "web-http-settings"
  listener_http        = "web-http-listener"
  listener_https       = "web-https-listener"
  routing_rule_http    = "web-routing-rule"
  routing_rule_https   = "web-routing-rule-https"
  redirect_config_name = "http-to-https-redirect"
  probe_name           = "web-http-probe"
  ssl_cert_name        = "appgw-ssl-cert"
}

resource "azurerm_application_gateway" "this" {
  name                = local.appgw_name
  location            = var.location
  resource_group_name = var.resource_group_name
  firewall_policy_id  = azurerm_web_application_firewall_policy.this.id
  tags                = var.tags

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }

  # Enforce TLS 1.2+ via an explicit Custom policy. Predefined policies do not
  # surface min_protocol_version to scanners, so CKV_AZURE_218 only passes with
  # an explicit value here. The HTTPS listener inherits this baseline.
  ssl_policy {
    policy_type          = "Custom"
    min_protocol_version = "TLSv1_2"
    cipher_suites = [
      "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384",
      "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256",
    ]
  }

  # User-Assigned Managed Identity required for AppGw to pull the cert from KV.
  dynamic "identity" {
    for_each = var.enable_https ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [var.user_assigned_identity_id]
    }
  }

  gateway_ip_configuration {
    name      = "appgw-ip-configuration"
    subnet_id = var.appgw_subnet_id
  }

  # Declare 443 first when HTTPS is enabled.
  dynamic "frontend_port" {
    for_each = var.enable_https ? [1] : []
    content {
      name = local.frontend_port_443
      port = 443
    }
  }

  frontend_port {
    name = local.frontend_port_80
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_name
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name         = local.backend_pool_name
    ip_addresses = [var.web_backend_ip]
  }

  probe {
    name                                      = local.probe_name
    protocol                                  = "Http"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200-399"]
    }
  }

  backend_http_settings {
    name                                = local.http_setting_name
    cookie_based_affinity               = "Disabled"
    port                                = 80
    protocol                            = "Http"
    request_timeout                     = 30
    probe_name                          = local.probe_name
    pick_host_name_from_backend_address = true
  }

  # SSL certificate is sourced from Key Vault via the User-Assigned identity.
  # Using the versionless secret ID enables automatic rotation when the cert
  # is renewed in Key Vault.
  dynamic "ssl_certificate" {
    for_each = var.enable_https ? [1] : []
    content {
      name                = local.ssl_cert_name
      key_vault_secret_id = var.ssl_certificate_secret_id
    }
  }

  # HTTPS listener is declared before the HTTP listener so that
  # CKV_AZURE_217 (which inspects http_listener[0].protocol) passes.
  dynamic "http_listener" {
    for_each = var.enable_https ? [1] : []
    content {
      name                           = local.listener_https
      frontend_ip_configuration_name = local.frontend_ip_name
      frontend_port_name             = local.frontend_port_443
      protocol                       = "Https"
      ssl_certificate_name           = local.ssl_cert_name
    }
  }

  http_listener {
    name                           = local.listener_http
    frontend_ip_configuration_name = local.frontend_ip_name
    frontend_port_name             = local.frontend_port_80
    protocol                       = "Http"
  }

  # Permanent HTTP -> HTTPS redirect, preserving path + query string.
  dynamic "redirect_configuration" {
    for_each = var.enable_https ? [1] : []
    content {
      name                 = local.redirect_config_name
      redirect_type        = "Permanent"
      target_listener_name = local.listener_https
      include_path         = true
      include_query_string = true
    }
  }

  # HTTPS routing rule: terminate TLS and forward to the web backend.
  dynamic "request_routing_rule" {
    for_each = var.enable_https ? [1] : []
    content {
      name                       = local.routing_rule_https
      rule_type                  = "Basic"
      http_listener_name         = local.listener_https
      backend_address_pool_name  = local.backend_pool_name
      backend_http_settings_name = local.http_setting_name
      priority                   = 100
    }
  }

  # HTTP routing rule: redirect to HTTPS when enabled, otherwise forward to backend.
  request_routing_rule {
    name                        = local.routing_rule_http
    rule_type                   = "Basic"
    http_listener_name          = local.listener_http
    priority                    = 110
    backend_address_pool_name   = var.enable_https ? null : local.backend_pool_name
    backend_http_settings_name  = var.enable_https ? null : local.http_setting_name
    redirect_configuration_name = var.enable_https ? local.redirect_config_name : null
  }

  lifecycle {
    precondition {
      condition     = !var.enable_https || (var.ssl_certificate_secret_id != null && var.user_assigned_identity_id != null)
      error_message = "enable_https requires both ssl_certificate_secret_id and user_assigned_identity_id."
    }
  }

  depends_on = [azurerm_subnet_network_security_group_association.appgw]
}

###############################################################################
# Diagnostic settings
###############################################################################
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                       = "${var.prefix}-fw-diag"
  target_resource_id         = azurerm_firewall.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "appgw" {
  name                       = "${var.prefix}-appgw-diag"
  target_resource_id         = azurerm_application_gateway.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "bastion" {
  name                       = "${var.prefix}-bastion-diag"
  target_resource_id         = azurerm_bastion_host.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}
