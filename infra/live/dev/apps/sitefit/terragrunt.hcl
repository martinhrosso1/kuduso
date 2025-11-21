# Terragrunt configuration for sitefit app stack

# Include root configuration
include "root" {
  path = find_in_parent_folders()
}

# Dependencies
dependency "core" {
  config_path = "../../shared/core"
  
  mock_outputs = {
    resource_group_name         = "mock-rg"
    location                    = "westeurope"
    aca_environment_id          = "mock-cae-id"
    acr_server                  = "mockacr.azurecr.io"
    servicebus_namespace_id     = "mock-sb-id"
    key_vault_id                = "mock-kv-id"
    key_vault_uri               = "https://mock-kv.vault.azure.net/"
  }
}

# Point to the app-stack module
terraform {
  source = "../../../../modules/app-stack"
}

# Module inputs
inputs = {
  name_prefix         = "kuduso-dev"
  app_name            = "sitefit"
  resource_group_name = dependency.core.outputs.resource_group_name
  location            = dependency.core.outputs.location
  
  # Container Apps Environment
  container_apps_environment_id = dependency.core.outputs.aca_environment_id
  
  # Container Registry
  container_registry_server = dependency.core.outputs.acr_server
  
  # Service Bus
  servicebus_namespace_id = dependency.core.outputs.servicebus_namespace_id
  
  # Key Vault
  key_vault_id  = dependency.core.outputs.key_vault_id
  key_vault_uri = dependency.core.outputs.key_vault_uri
  
  # AppServer URL (internal) - using internal FQDN with standard HTTP port
  appserver_url = "http://kuduso-dev-appserver.internal.blackwave-77d88b66.westeurope.azurecontainerapps.io:80/gh/{definition}:{version}/solve"
  
  # API Configuration
  api_image        = "api-fastapi:4be8016"
  api_cpu          = "0.5"
  api_memory       = "1Gi"
  api_min_replicas = 1
  api_max_replicas = 5
  api_port         = 8000
  
  # Worker Configuration
  worker_image        = "worker-fastapi:504-retry-fix"
  worker_cpu          = "0.5"
  worker_memory       = "1Gi"
  worker_min_replicas = 0  # Scale to zero when no messages
  worker_max_replicas = 10
  worker_port         = 8080
  
  # KEDA Configuration
  keda_queue_length     = 5    # Scale up when > 5 messages per replica
  keda_polling_interval = 30   # Check queue every 30 seconds
  keda_cooldown_period  = 300  # Wait 5 minutes before scaling down
  
  # Secret Names (from Key Vault)
  database_url_secret_name         = "DATABASE-URL"
  servicebus_connection_secret_name = "SERVICEBUS-CONN"
}
