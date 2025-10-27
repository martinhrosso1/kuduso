# app-stack module: Service Bus queue + API + Worker Container Apps for an application

locals {
  tags = merge(
    var.common_tags,
    {
      module      = "app-stack"
      application = var.app_name
    }
  )
  
  queue_name = "${var.app_name}-queue"
}

data "azurerm_client_config" "current" {}

# Service Bus Queue for the application
resource "azurerm_servicebus_queue" "app_queue" {
  name         = local.queue_name
  namespace_id = var.servicebus_namespace_id
  
  # Queue settings
  enable_partitioning                   = true
  max_delivery_count                    = 10
  default_message_ttl                   = "P14D" # 14 days
  lock_duration                         = "PT5M" # 5 minutes
  duplicate_detection_history_time_window = "PT10M"
  
  # Dead letter queue
  dead_lettering_on_message_expiration = true
}

# Managed Identity for API app
resource "azurerm_user_assigned_identity" "api" {
  name                = "${var.name_prefix}-${var.app_name}-api-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
  
  tags = local.tags
}

# Managed Identity for Worker app
resource "azurerm_user_assigned_identity" "worker" {
  name                = "${var.name_prefix}-${var.app_name}-worker-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
  
  tags = local.tags
}

# Role Assignment: API - Key Vault Secrets User
resource "azurerm_role_assignment" "api_kv_secrets" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.api.principal_id
}

# Role Assignment: API - ACR Pull
resource "azurerm_role_assignment" "api_acr_pull" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.api.principal_id
}

# Role Assignment: Worker - Key Vault Secrets User
resource "azurerm_role_assignment" "worker_kv_secrets" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.worker.principal_id
}

# Role Assignment: Worker - ACR Pull
resource "azurerm_role_assignment" "worker_acr_pull" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.worker.principal_id
}

# Role Assignment: Worker - Service Bus Data Receiver
resource "azurerm_role_assignment" "worker_servicebus" {
  scope                = var.servicebus_namespace_id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.worker.principal_id
}

# API Container App (External)
resource "azurerm_container_app" "api" {
  name                         = "${var.name_prefix}-${var.app_name}-api"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_apps_environment_id
  revision_mode                = "Single"
  
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.api.id]
  }
  
  registry {
    server   = var.container_registry_server
    identity = azurerm_user_assigned_identity.api.id
  }
  
  ingress {
    external_enabled = true
    target_port      = var.api_port
    
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
  
  template {
    min_replicas = var.api_min_replicas
    max_replicas = var.api_max_replicas
    
    container {
      name   = "api"
      image  = "${var.container_registry_server}/${var.api_image}"
      cpu    = var.api_cpu
      memory = var.api_memory
      
      env {
        name  = "NODE_ENV"
        value = "production"
      }
      
      env {
        name  = "PORT"
        value = tostring(var.api_port)
      }
      
      env {
        name  = "APP_NAME"
        value = var.app_name
      }
      
      env {
        name  = "APPSERVER_URL"
        value = var.appserver_url
      }
      
      env {
        name  = "QUEUE_NAME"
        value = local.queue_name
      }
      
      # Database URL from Key Vault
      env {
        name        = "DATABASE_URL"
        secret_name = "database-url"
      }
      
      # Service Bus connection from Key Vault
      env {
        name        = "SERVICEBUS_CONNECTION_STRING"
        secret_name = "servicebus-connection"
      }
      
      # Managed identity for Azure SDK
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.api.client_id
      }
      
      liveness_probe {
        transport = "HTTP"
        port      = var.api_port
        path      = "/health"
        
        initial_delay           = 10
        interval_seconds        = 30
        timeout                 = 5
        failure_count_threshold = 3
      }
      
      readiness_probe {
        transport = "HTTP"
        port      = var.api_port
        path      = "/ready"
        
        interval_seconds        = 10
        timeout                 = 3
        failure_count_threshold = 3
        success_count_threshold = 1
      }
    }
  }
  
  # Secrets from Key Vault
  secret {
    name                = "database-url"
    key_vault_secret_id = "${var.key_vault_uri}secrets/${var.database_url_secret_name}"
    identity            = azurerm_user_assigned_identity.api.id
  }
  
  secret {
    name                = "servicebus-connection"
    key_vault_secret_id = "${var.key_vault_uri}secrets/${var.servicebus_connection_secret_name}"
    identity            = azurerm_user_assigned_identity.api.id
  }
  
  tags = local.tags
  
  depends_on = [
    azurerm_role_assignment.api_kv_secrets,
    azurerm_role_assignment.api_acr_pull,
    azurerm_servicebus_queue.app_queue
  ]
}

# Worker Container App (Internal, KEDA Scaled)
resource "azurerm_container_app" "worker" {
  name                         = "${var.name_prefix}-${var.app_name}-worker"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_apps_environment_id
  revision_mode                = "Single"
  
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.worker.id]
  }
  
  registry {
    server   = var.container_registry_server
    identity = azurerm_user_assigned_identity.worker.id
  }
  
  # No ingress - worker processes queue messages
  
  template {
    min_replicas = var.worker_min_replicas
    max_replicas = var.worker_max_replicas
    
    container {
      name   = "worker"
      image  = "${var.container_registry_server}/${var.worker_image}"
      cpu    = var.worker_cpu
      memory = var.worker_memory
      
      env {
        name  = "NODE_ENV"
        value = "production"
      }
      
      env {
        name  = "APP_NAME"
        value = var.app_name
      }
      
      env {
        name  = "APPSERVER_URL"
        value = var.appserver_url
      }
      
      env {
        name  = "QUEUE_NAME"
        value = local.queue_name
      }
      
      # Database URL from Key Vault
      env {
        name        = "DATABASE_URL"
        secret_name = "database-url"
      }
      
      # Service Bus connection from Key Vault
      env {
        name        = "SERVICEBUS_CONNECTION_STRING"
        secret_name = "servicebus-connection"
      }
      
      # Managed identity for Azure SDK
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.worker.client_id
      }
      
      liveness_probe {
        transport = "TCP"
        port      = var.worker_port
        
        initial_delay           = 10
        interval_seconds        = 30
        timeout                 = 5
        failure_count_threshold = 3
      }
    }
  }
  
  # KEDA Scale Rule - Azure Service Bus Queue
  # Note: In AzureRM provider 3.x, this is configured differently
  # We'll use the newer scale block format
  
  # Secrets from Key Vault
  secret {
    name                = "database-url"
    key_vault_secret_id = "${var.key_vault_uri}secrets/${var.database_url_secret_name}"
    identity            = azurerm_user_assigned_identity.worker.id
  }
  
  secret {
    name                = "servicebus-connection"
    key_vault_secret_id = "${var.key_vault_uri}secrets/${var.servicebus_connection_secret_name}"
    identity            = azurerm_user_assigned_identity.worker.id
  }
  
  tags = local.tags
  
  depends_on = [
    azurerm_role_assignment.worker_kv_secrets,
    azurerm_role_assignment.worker_acr_pull,
    azurerm_role_assignment.worker_servicebus,
    azurerm_servicebus_queue.app_queue
  ]
}

# KEDA Scaler for Worker (using custom scale rule)
# Note: The azurerm_container_app resource doesn't fully support KEDA scale rules in Terraform yet
# We'll need to apply this via Azure CLI or ARM template as a post-deployment step
# For now, we document the required configuration
