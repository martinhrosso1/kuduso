# Terragrunt configuration for shared-core in dev environment

# Include root configuration
include "root" {
  path = find_in_parent_folders()
}

# Point to the shared-core module
terraform {
  source = "../../../../modules/shared-core"
}

# Module inputs
inputs = {
  name_prefix        = "kuduso-dev"
  location           = "westeurope"
  environment        = "dev"
  log_retention_days = 30
  servicebus_sku     = "Standard"
}
