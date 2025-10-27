# Outputs for app-stack module

# Service Bus Queue
output "queue_id" {
  description = "ID of the Service Bus queue"
  value       = azurerm_servicebus_queue.app_queue.id
}

output "queue_name" {
  description = "Name of the Service Bus queue"
  value       = azurerm_servicebus_queue.app_queue.name
}

# API Container App
output "api_id" {
  description = "ID of the API Container App"
  value       = azurerm_container_app.api.id
}

output "api_name" {
  description = "Name of the API Container App"
  value       = azurerm_container_app.api.name
}

output "api_fqdn" {
  description = "FQDN of the API Container App"
  value       = azurerm_container_app.api.ingress[0].fqdn
}

output "api_url" {
  description = "Full HTTPS URL of the API"
  value       = "https://${azurerm_container_app.api.ingress[0].fqdn}"
}

output "api_identity_principal_id" {
  description = "Principal ID of the API managed identity"
  value       = azurerm_user_assigned_identity.api.principal_id
}

output "api_identity_client_id" {
  description = "Client ID of the API managed identity"
  value       = azurerm_user_assigned_identity.api.client_id
}

output "api_latest_revision_name" {
  description = "Latest revision name of the API"
  value       = azurerm_container_app.api.latest_revision_name
}

# Worker Container App
output "worker_id" {
  description = "ID of the Worker Container App"
  value       = azurerm_container_app.worker.id
}

output "worker_name" {
  description = "Name of the Worker Container App"
  value       = azurerm_container_app.worker.name
}

output "worker_identity_principal_id" {
  description = "Principal ID of the Worker managed identity"
  value       = azurerm_user_assigned_identity.worker.principal_id
}

output "worker_identity_client_id" {
  description = "Client ID of the Worker managed identity"
  value       = azurerm_user_assigned_identity.worker.client_id
}

output "worker_latest_revision_name" {
  description = "Latest revision name of the Worker"
  value       = azurerm_container_app.worker.latest_revision_name
}

# Application Info
output "app_name" {
  description = "Application name"
  value       = var.app_name
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    app_name    = var.app_name
    queue_name  = local.queue_name
    api_url     = "https://${azurerm_container_app.api.ingress[0].fqdn}"
    api_replicas = "${var.api_min_replicas}-${var.api_max_replicas}"
    worker_replicas = "${var.worker_min_replicas}-${var.worker_max_replicas}"
  }
}
