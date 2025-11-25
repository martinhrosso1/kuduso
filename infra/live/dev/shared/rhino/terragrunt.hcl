# Terragrunt configuration for Rhino VM in dev environment

# Include root configuration
include "root" {
  path = find_in_parent_folders()
}

# Dependency on shared-core
dependency "core" {
  config_path = "../core"
  
  mock_outputs = {
    resource_group_name = "mock-rg"
    location            = "westeurope"
    key_vault_id        = "mock-kv-id"
  }
}

# Dependency on compute-gallery for custom VM image
dependency "gallery" {
  config_path = "../compute-gallery"
  
  mock_outputs = {
    image_version_id = "mock-image-id"
  }
}

# Dependency on AppServer to get ACA outbound IPs
dependency "appserver" {
  config_path = "../appserver"
  skip_outputs = false
  
  mock_outputs = {
    outbound_ip_addresses = ["0.0.0.0"]
  }
}

# Point to the rhino-vm module
terraform {
  source = "../../../../modules/rhino-vm"
}

# Module inputs
inputs = {
  name_prefix         = "kuduso-dev"
  resource_group_name = dependency.core.outputs.resource_group_name
  location            = dependency.core.outputs.location
  
  # Key Vault
  key_vault_id = dependency.core.outputs.key_vault_id
  
  # Custom Image from Compute Gallery
  # This image has Rhino 8 and Rhino.Compute pre-installed and configured
  source_image_id = dependency.gallery.outputs.image_version_id
  
  # VM Configuration
  vm_size         = "Standard_B2s" # Smallest suitable: 2 vCPUs, 4GB RAM (~$30/month)
  admin_username  = "rhinoadmin"
  admin_password  = get_env("RHINO_VM_PASSWORD", "ChangeMe123!_?_?") # Set via env var
  
  # Network Security
  # Update this with your current local PC public IP in CIDR format
  allowed_source_ip = get_env("MY_PUBLIC_IP", "178.41.184.249/32")
  
  # Azure Container Apps outbound IPs (for AppServer → Rhino.Compute connectivity)
  aca_outbound_ips = dependency.appserver.outputs.outbound_ip_addresses
  
  # Rhino.Compute
  rhino_compute_port = 8081
  
  # Cost Optimization
  enable_auto_shutdown   = true
  auto_shutdown_time     = "1900" # 7 PM
  auto_shutdown_timezone = "Central Europe Standard Time"
}
