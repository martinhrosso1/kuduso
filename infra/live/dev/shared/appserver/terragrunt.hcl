# Terragrunt configuration for shared AppServer in dev environment

# Include root configuration
include "root" {
  path = find_in_parent_folders()
}

# Dependencies
dependency "core" {
  config_path = "../core"
  
  mock_outputs = {
    resource_group_name    = "mock-rg"
    location               = "westeurope"
    aca_environment_id     = "mock-cae-id"
    acr_server             = "mockacr.azurecr.io"
    key_vault_id           = "mock-kv-id"
    key_vault_uri          = "https://mock-kv.vault.azure.net/"
  }
}

# Point to the shared-appserver module
terraform {
  source = "../../../../modules/shared-appserver"
}

# Module inputs
inputs = {
  name_prefix         = "kuduso-dev"
  resource_group_name = dependency.core.outputs.resource_group_name
  location            = dependency.core.outputs.location
  
  # Container Apps Environment
  container_apps_environment_id = dependency.core.outputs.aca_environment_id
  
  # Container Registry
  container_registry_server = dependency.core.outputs.acr_server
  
  # Image
  app_image = "appserver-node:6282cdd" # With /ready endpoint and contracts included
  
  # Key Vault
  key_vault_id  = dependency.core.outputs.key_vault_id
  key_vault_uri = dependency.core.outputs.key_vault_uri
  
  # Resources
  cpu    = "0.5"  # 0.5 vCPU
  memory = "1Gi"  # 1 GB RAM
  
  # Scaling
  min_replicas = 1
  max_replicas = 3
  
  # Network
  target_port      = 8080
  enable_ingress   = false # Internal only - accessed by API/Worker apps
  
  # Rhino.Compute
  rhino_compute_url = "http://20.73.173.209:8081" # Real Rhino VM (use mock if not ready)
  # rhino_compute_url = "http://mock-compute:8081" # Uncomment for mock
  
  # Secrets (Key Vault secret names)
  database_connection_string_secret_name = "DATABASE-URL"
  rhino_api_key_secret_name              = "COMPUTE-API-KEY"
}
