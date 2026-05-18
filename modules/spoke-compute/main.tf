###############################################################################
# Spoke compute module
#
# Provides:
#   - Web tier NSG (allow Application Gateway -> 80/443, Bastion -> 22)
#   - App tier NSG (allow Web subnet -> 8080, Bastion -> 22)
#   - One Linux VM per tier (Web Server, App Server)
###############################################################################

###############################################################################
# Web tier NSG
###############################################################################
resource "azurerm_network_security_group" "web" {
  name                = "${var.prefix}-web-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "Allow-AppGw-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = var.appgw_subnet_cidr
    destination_address_prefix = var.web_subnet_cidr
  }

  security_rule {
    name                       = "Allow-Bastion-SSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.bastion_subnet_cidr
    destination_address_prefix = var.web_subnet_cidr
  }

  # Application Gateway health probe traffic (ports 65200-65535) for v2 SKU
  security_rule {
    name                       = "Allow-AppGw-HealthProbes"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = var.web_subnet_id
  network_security_group_id = azurerm_network_security_group.web.id
}

###############################################################################
# App tier NSG
###############################################################################
resource "azurerm_network_security_group" "app" {
  name                = "${var.prefix}-app-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "Allow-Web-AppPort"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = var.web_subnet_cidr
    destination_address_prefix = var.app_subnet_cidr
  }

  security_rule {
    name                       = "Allow-Bastion-SSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.bastion_subnet_cidr
    destination_address_prefix = var.app_subnet_cidr
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = var.app_subnet_id
  network_security_group_id = azurerm_network_security_group.app.id
}

###############################################################################
# Auth mode: SSH key when provided, otherwise password.
###############################################################################
locals {
  use_ssh_key = length(trimspace(var.vm_admin_ssh_public_key)) > 0
}

###############################################################################
# Web tier VM
###############################################################################
resource "azurerm_network_interface" "web" {
  name                = "${var.prefix}-web-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.web_subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "web" {
  name                            = "${var.prefix}-web-vm"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.web_vm_size
  admin_username                  = var.vm_admin_username
  admin_password                  = local.use_ssh_key ? null : var.vm_admin_password
  disable_password_authentication = local.use_ssh_key
  allow_extension_operations      = var.allow_vm_extensions
  network_interface_ids           = [azurerm_network_interface.web.id]
  tags                            = var.tags

  dynamic "admin_ssh_key" {
    for_each = local.use_ssh_key ? [1] : []
    content {
      username   = var.vm_admin_username
      public_key = var.vm_admin_ssh_public_key
    }
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  boot_diagnostics {}
}

###############################################################################
# App tier VM
###############################################################################
resource "azurerm_network_interface" "app" {
  name                = "${var.prefix}-app-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.app_subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "app" {
  name                            = "${var.prefix}-app-vm"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.app_vm_size
  admin_username                  = var.vm_admin_username
  admin_password                  = local.use_ssh_key ? null : var.vm_admin_password
  disable_password_authentication = local.use_ssh_key
  allow_extension_operations      = var.allow_vm_extensions
  network_interface_ids           = [azurerm_network_interface.app.id]
  tags                            = var.tags

  dynamic "admin_ssh_key" {
    for_each = local.use_ssh_key ? [1] : []
    content {
      username   = var.vm_admin_username
      public_key = var.vm_admin_ssh_public_key
    }
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  boot_diagnostics {}
}
