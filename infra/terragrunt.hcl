# Root Terragrunt configuration
# Provides common settings for all modules

locals {
  # Environment-specific values
  env = "dev"
  
  # Common tags for all resources
  common_tags = {
    project     = "kuduso"
    managed_by  = "terragrunt"
    repository  = "kuduso"
  }
}

# Configure remote state in Azure Storage
remote_state {
  backend = "azurerm"
  
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  
  config = {
    resource_group_name  = "kuduso-tfstate-rg"
    storage_account_name = get_env("TF_STATE_STORAGE_ACCOUNT", "kudusotfstate")
    container_name       = "tfstate"
    key                  = "${path_relative_to_include()}/terraform.tfstate"
  }
}

# Generate provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.6"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true  # We'll register providers manually as needed
  
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}
EOF
}

# Input variables available to all modules
inputs = {
  common_tags = local.common_tags
}
