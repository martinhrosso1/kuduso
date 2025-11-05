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
  
  # Enable System-assigned Managed Identity
  identity {
    type = "SystemAssigned"
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

# Custom Script Extension - Automated Rhino.Compute Setup
# Runs the automated setup script directly from the repository
# Note: Rhino 8 installation (script 09) must still be done manually due to licensing
resource "azurerm_virtual_machine_extension" "rhino_setup" {
  name                 = "RhinoComputeSetup"
  virtual_machine_id   = azurerm_windows_virtual_machine.main.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  
  # Two-stage approach to avoid command line length limits:
  # 1. Write the base64-encoded script content to a file
  # 2. Decode and execute the script file
  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -ExecutionPolicy Bypass -Command \"[System.IO.Directory]::CreateDirectory('C:\\rhino-setup') | Out-Null; [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(var.setup_script_content)}')) | Out-File -FilePath 'C:\\rhino-setup\\00-automated-setup.ps1' -Encoding UTF8 -Force; & 'C:\\rhino-setup\\00-automated-setup.ps1'\""
  })
  
  tags = local.tags
}

# Key Vault Access Policy - Grant VM's Managed Identity access to secrets
resource "azurerm_key_vault_access_policy" "vm_secrets" {
  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_windows_virtual_machine.main.identity[0].tenant_id
  object_id    = azurerm_windows_virtual_machine.main.identity[0].principal_id
  
  secret_permissions = [
    "Get",
    "List"
  ]
}
