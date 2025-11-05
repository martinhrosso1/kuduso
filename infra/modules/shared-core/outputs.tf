# Outputs for shared-core module

# Resource Group
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region"
  value       = azurerm_resource_group.main.location
}

# Container Registry
output "acr_id" {
  description = "ID of the Container Registry"
  value       = azurerm_container_registry.main.id
}

output "acr_name" {
  description = "Name of the Container Registry"
  value       = azurerm_container_registry.main.name
}

output "acr_server" {
  description = "Login server for the Container Registry"
  value       = azurerm_container_registry.main.login_server
}

# Log Analytics
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

# Key Vault
output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Storage
output "storage_account_id" {
  description = "ID of the Storage Account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_name" {
  description = "Name of the Storage Account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_key" {
  description = "Primary key of the Storage Account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "artifacts_container_name" {
  description = "Name of the artifacts blob container"
  value       = azurerm_storage_container.artifacts.name
}

output "vm_scripts_container_name" {
  description = "Name of the VM scripts blob container"
  value       = azurerm_storage_container.vm_scripts.name
}

# Service Bus
output "servicebus_namespace_id" {
  description = "ID of the Service Bus Namespace"
  value       = azurerm_servicebus_namespace.main.id
}

output "servicebus_namespace_name" {
  description = "Name of the Service Bus Namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "servicebus_connection_string" {
  description = "Connection string for Service Bus"
  value       = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive   = true
}

# Container Apps Environment
output "aca_environment_id" {
  description = "ID of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.id
}

output "aca_environment_name" {
  description = "Name of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.name
}

output "aca_environment_default_domain" {
  description = "Default domain of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.default_domain
}
