# shared-appserver module: Container App for shared contract validation & compute routing

locals {
  tags = merge(
    var.common_tags,
    {
      module  = "shared-appserver"
      purpose = "contract-validation-compute"
    }
  )
}

# Managed Identity for AppServer
resource "azurerm_user_assigned_identity" "appserver" {
  name                = "${var.name_prefix}-appserver-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
  
  tags = local.tags
}

# Role Assignment: Key Vault Secrets User
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.appserver.principal_id
}

# Role Assignment: ACR Pull (using the provided identity from platform)
resource "azurerm_role_assignment" "acr_pull" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.appserver.principal_id
}

data "azurerm_client_config" "current" {}

# Container App for AppServer
resource "azurerm_container_app" "appserver" {
  name                         = "${var.name_prefix}-appserver"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_apps_environment_id
  revision_mode                = "Single"
  
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.appserver.id]
  }
  
  registry {
    server   = var.container_registry_server
    identity = azurerm_user_assigned_identity.appserver.id
  }
  
  ingress {
    external_enabled = var.enable_ingress
    target_port      = var.target_port
    
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
  
  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas
    
    container {
      name   = "appserver"
      image  = "${var.container_registry_server}/${var.app_image}"
      cpu    = var.cpu
      memory = var.memory
      
      env {
        name  = "NODE_ENV"
        value = "production"
      }
      
      env {
        name  = "PORT"
        value = tostring(var.target_port)
      }
      
      env {
        name  = "COMPUTE_URL"
        value = var.rhino_compute_url
      }
      
      # Database connection string from Key Vault
      env {
        name        = "DATABASE_URL"
        secret_name = "db-connection-string"
      }
      
      # Rhino.Compute API key from Key Vault
      env {
        name        = "COMPUTE_API_KEY"
        secret_name = "compute-api-key"
      }
      
      # Managed identity for Key Vault access
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.appserver.client_id
      }
      
      liveness_probe {
        transport = "HTTP"
        port      = var.target_port
        path      = "/health"
        
        initial_delay           = 10
        interval_seconds        = 30
        timeout                 = 5
        failure_count_threshold = 3
      }
      
      readiness_probe {
        transport = "HTTP"
        port      = var.target_port
        path      = "/ready"
        
        interval_seconds        = 10
        timeout                 = 3
        failure_count_threshold = 3
        success_count_threshold = 1
      }
      
      startup_probe {
        transport = "HTTP"
        port      = var.target_port
        path      = "/health"
        
        interval_seconds        = 5
        timeout                 = 3
        failure_count_threshold = 10
      }
    }
  }
  
  # Secrets from Key Vault
  secret {
    name                = "db-connection-string"
    key_vault_secret_id = "${var.key_vault_uri}secrets/${var.database_connection_string_secret_name}"
    identity            = azurerm_user_assigned_identity.appserver.id
  }
  
  secret {
    name                = "compute-api-key"
    key_vault_secret_id = "${var.key_vault_uri}secrets/${var.rhino_api_key_secret_name}"
    identity            = azurerm_user_assigned_identity.appserver.id
  }
  
  tags = local.tags
  
  depends_on = [
    azurerm_role_assignment.kv_secrets_user,
    azurerm_role_assignment.acr_pull
  ]
}
