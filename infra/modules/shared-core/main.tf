# shared-core module: Platform-level shared resources
# Creates: RG, ACR, Log Analytics, Key Vault, Storage, Service Bus, ACA Environment

locals {
  name_suffix = substr(md5("${var.name_prefix}-${var.location}"), 0, 6)
  
  tags = merge(
    var.common_tags,
    {
      environment = var.environment
      module      = "shared-core"
    }
  )
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

# Container Registry
resource "azurerm_container_registry" "main" {
  name                = replace("${var.name_prefix}acr${local.name_suffix}", "-", "")
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false # Use managed identity for pulls
  
  tags = local.tags
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.name_prefix}-law"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = local.tags
}

# Key Vault
resource "azurerm_key_vault" "main" {
  name                       = "${var.name_prefix}-kv-${local.name_suffix}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false # Enable in production
  
  enable_rbac_authorization = true # Use RBAC instead of access policies
  
  tags = local.tags
}

# Storage Account (for artifacts/blobs)
resource "azurerm_storage_account" "main" {
  name                     = replace("${var.name_prefix}st${local.name_suffix}", "-", "")
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  
  blob_properties {
    versioning_enabled = false
    
    delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.tags
}

# Blob container for artifacts
resource "azurerm_storage_container" "artifacts" {
  name                  = "artifacts"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Service Bus Namespace
resource "azurerm_servicebus_namespace" "main" {
  name                = "${var.name_prefix}-servicebus"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.servicebus_sku
  
  tags = local.tags
}

# Container Apps Environment
resource "azurerm_container_app_environment" "main" {
  name                       = "${var.name_prefix}-aca-env"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  tags = local.tags
}

# Data source for current Azure config
data "azurerm_client_config" "current" {}
