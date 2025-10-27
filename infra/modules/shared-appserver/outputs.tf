# Outputs for shared-appserver module

output "app_id" {
  description = "ID of the Container App"
  value       = azurerm_container_app.appserver.id
}

output "app_name" {
  description = "Name of the Container App"
  value       = azurerm_container_app.appserver.name
}

output "app_fqdn" {
  description = "FQDN of the Container App (if ingress enabled)"
  value       = var.enable_ingress ? azurerm_container_app.appserver.ingress[0].fqdn : null
}

output "app_url" {
  description = "Full URL of the Container App"
  value       = var.enable_ingress ? "https://${azurerm_container_app.appserver.ingress[0].fqdn}" : "internal-only"
}

output "identity_principal_id" {
  description = "Principal ID of the managed identity"
  value       = azurerm_user_assigned_identity.appserver.principal_id
}

output "identity_client_id" {
  description = "Client ID of the managed identity"
  value       = azurerm_user_assigned_identity.appserver.client_id
}

output "identity_id" {
  description = "ID of the managed identity"
  value       = azurerm_user_assigned_identity.appserver.id
}

output "latest_revision_name" {
  description = "Latest revision name"
  value       = azurerm_container_app.appserver.latest_revision_name
}

output "latest_revision_fqdn" {
  description = "Latest revision FQDN"
  value       = azurerm_container_app.appserver.latest_revision_fqdn
}

output "outbound_ip_addresses" {
  description = "Outbound IP addresses"
  value       = azurerm_container_app.appserver.outbound_ip_addresses
}
