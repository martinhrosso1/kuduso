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
  
  # VM Configuration
  vm_size         = "Standard_B2s" # Smallest suitable: 2 vCPUs, 4GB RAM (~$30/month)
  admin_username  = "rhinoadmin"
  admin_password  = get_env("RHINO_VM_PASSWORD", "ChangeMe123!") # Set via env var
  
  # Network Security
  allowed_source_ip = get_env("MY_PUBLIC_IP", "0.0.0.0/0") # Set to your IP!
  
  # Rhino.Compute
  rhino_compute_port = 8081
  
  # Cost Optimization
  enable_auto_shutdown   = true
  auto_shutdown_time     = "1900" # 7 PM
  auto_shutdown_timezone = "Central Europe Standard Time"
}
