terraform {

  required_version = ">=0.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}

provider "azurerm" {
  features {}
}


# Create resource group
resource "azurerm_resource_group" "rg" {
  name     = "RG_test"
  location = "australiaeast"
}

# Create virtual network
resource "azurerm_virtual_network" "vn_test" {
  name                = "VN_test"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create subnetbe01
resource "azurerm_subnet" "subnetbe01" {
  name                 = "subnetbe01"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vn_test.name
  address_prefixes     = ["10.0.20.0/24"]
}

# Create subnetfe01
resource "azurerm_subnet" "subnetfe01" {
  name                 = "subnetfe01"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vn_test.name
  address_prefixes     = ["10.0.10.0/24"]
}

# Create public IP for VMLUE01
resource "azurerm_public_ip" "publicip_vmlue01" {
  name                = "publicip_vmlue01"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}


# Create security group for VMLUE01
resource "azurerm_network_security_group" "for_vmlue01" {
  name                = "for_vmlue01"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowFTP"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["20-21", "21100-21110"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create security group for subnetbe01
resource "azurerm_network_security_group" "for_subnetbe01" {
  name                = "for_subnetbe01"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowInboundFromVMLUE"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.0.20.10/32"
    destination_address_prefix = "10.0.20.0/24"
  }

  security_rule {
    name                       = "DenyVnetInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "10.0.20.0/24"
  }

}

# Connect the security group to subnetbe01
resource "azurerm_subnet_network_security_group_association" "assoc_subnetbe01" {
  subnet_id                 = azurerm_subnet.subnetbe01.id
  network_security_group_id = azurerm_network_security_group.for_subnetbe01.id
}


# Create  network interface
resource "azurerm_network_interface" "nicfe_vmlue01" {
  name                = "nicfe_vmlue01"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "test"
    subnet_id                     = azurerm_subnet.subnetfe01.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.publicip_vmlue01.id
  }
}

# Connect security group to interface
resource "azurerm_network_interface_security_group_association" "assoc_vmlue01" {
  network_interface_id      = azurerm_network_interface.nicfe_vmlue01.id
  network_security_group_id = azurerm_network_security_group.for_vmlue01.id
}

# Create network interface
resource "azurerm_network_interface" "nicbe_vmlue01" {
  name                = "nicbe_vmlue01"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal_static"
    subnet_id                     = azurerm_subnet.subnetbe01.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.20.10"
  }
}

# Create SSH key
resource "tls_private_key" "ssh_vmlue01" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "vmlue01" {
  name                = "vmlue01"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  network_interface_ids = [
    azurerm_network_interface.nicfe_vmlue01.id,
    azurerm_network_interface.nicbe_vmlue01.id
  ]
  size = "Standard_B1s"

  os_disk {
    caching              = "None"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  computer_name                   = "vmlue01"
  admin_username                  = "sadmin"
  custom_data                     = filebase64("ss/ans.yaml")
  disable_password_authentication = true

  admin_ssh_key {
    username   = "sadmin"
    public_key = tls_private_key.ssh_vmlue01.public_key_openssh
  }
}


# Create network interfaces
resource "azurerm_network_interface" "nic_vmlu" {
  count               = 2
  name                = "NIC_VMLU0${count.index + 1}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal_static"
    subnet_id                     = azurerm_subnet.subnetbe01.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.20.1${count.index + 1}"
  }
}

# Create SSH keys
resource "tls_private_key" "ssh_vmlu" {
  count     = 2
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create virtual machines
resource "azurerm_linux_virtual_machine" "vmlu" {
  count                 = 2
  name                  = "VMLU0${count.index + 1}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [element(azurerm_network_interface.nic_vmlu.*.id, count.index)]
  size                  = "Standard_B1s"

  os_disk {
    caching              = "None"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  computer_name                   = "vmlu0${count.index + 1}"
  admin_username                  = "sadmin"
  custom_data                     = filebase64("ss/publickey.yaml")
  disable_password_authentication = true

  admin_ssh_key {
    username   = "sadmin"
    public_key = element(tls_private_key.ssh_vmlu.*.public_key_openssh, count.index)
  }
}
