# rhino-vm module: Windows VM for Rhino.Compute (dev environment)

locals {
  tags = merge(
    var.common_tags,
    {
      module = "rhino-vm"
      purpose = "rhino-compute"
    }
  )
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.name_prefix}-rhino-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = ["10.0.0.0/16"]
  
  tags = local.tags
}

# Subnet
resource "azurerm_subnet" "main" {
  name                 = "${var.name_prefix}-rhino-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Public IP
resource "azurerm_public_ip" "main" {
  name                = "${var.name_prefix}-rhino-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = local.tags
}

# Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = "${var.name_prefix}-rhino-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
  
  # Allow RDP from your IP (for management)
  security_rule {
    name                       = "AllowRDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.allowed_source_ip
    destination_address_prefix = "*"
  }
  
  # Allow HTTP (Rhino.Compute) from your IP
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = var.allowed_source_ip
    destination_address_prefix = "*"
  }
  
  # Allow Rhino.Compute port from your IP
  security_rule {
    name                       = "AllowRhinoCompute"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.rhino_compute_port)
    source_address_prefix      = var.allowed_source_ip
    destination_address_prefix = "*"
  }
  
  # Allow Windows Admin Center from your IP
  security_rule {
    name                       = "AllowWindowsAdminCenter"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6516"
    source_address_prefix      = var.allowed_source_ip
    destination_address_prefix = "*"
  }
  
  # Deny all other inbound
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = local.tags
}

# Network Interface
resource "azurerm_network_interface" "main" {
  name                = "${var.name_prefix}-rhino-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
  
  tags = local.tags
}

# Associate NSG with NIC
resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Windows Virtual Machine
resource "azurerm_windows_virtual_machine" "main" {
  name                = "${var.name_prefix}-rhino-vm"
  computer_name       = "rhino-vm" # Windows computer name max 15 chars
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  
  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS" # Use Standard for cost savings
  }
  
  # Windows Server 2022 Datacenter
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }
  
  # Enable boot diagnostics
  boot_diagnostics {
    storage_account_uri = null # Uses managed storage
  }
  
  tags = local.tags
}

# Auto-shutdown schedule (to save costs)
resource "azurerm_dev_test_global_vm_shutdown_schedule" "main" {
  count              = var.enable_auto_shutdown ? 1 : 0
  virtual_machine_id = azurerm_windows_virtual_machine.main.id
  location           = var.location
  enabled            = true
  
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone
  
  notification_settings {
    enabled = false
  }
  
  tags = local.tags
}

# Custom Script Extension - Install Rhino.Compute
# Note: This is a placeholder. In reality, you need to:
# 1. Upload Rhino.Compute installer to Azure Blob or use direct download
# 2. Create PowerShell script to install and configure
# 3. Reference it here
resource "azurerm_virtual_machine_extension" "rhino_setup" {
  name                 = "RhinoComputeSetup"
  virtual_machine_id   = azurerm_windows_virtual_machine.main.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  
  # Create placeholder file - actual Rhino.Compute installation is manual
  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -Command \"New-Item -Path C:\\rhino-placeholder.txt -ItemType File -Force; Write-Output 'Rhino.Compute placeholder - manual installation required'\""
  })
  
  tags = local.tags
}
