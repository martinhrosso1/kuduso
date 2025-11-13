# Variables for shared-appserver module

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "container_apps_environment_id" {
  description = "ID of the Container Apps Environment"
  type        = string
}

variable "container_registry_server" {
  description = "ACR server URL"
  type        = string
}

variable "app_image" {
  description = "Container image for AppServer (e.g., 'appserver-node:latest')"
  type        = string
  default     = "appserver-node:latest"
}

variable "key_vault_id" {
  description = "ID of the Key Vault"
  type        = string
}

variable "key_vault_uri" {
  description = "URI of the Key Vault (e.g., https://vault-name.vault.azure.net/)"
  type        = string
}

variable "cpu" {
  description = "CPU allocation (e.g., '0.5', '1')"
  type        = string
  default     = "0.5"
}

variable "memory" {
  description = "Memory allocation (e.g., '1Gi', '2Gi')"
  type        = string
  default     = "1Gi"
}

variable "min_replicas" {
  description = "Minimum number of replicas"
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum number of replicas"
  type        = number
  default     = 3
}

variable "target_port" {
  description = "Container port"
  type        = number
  default     = 8080
}

variable "rhino_compute_url" {
  description = "URL for Rhino.Compute service"
  type        = string
  default     = "http://mock-compute:8081" # Default to mock
}

variable "database_connection_string_secret_name" {
  description = "Name of the database connection string secret in Key Vault"
  type        = string
  default     = "DB-CONNECTION-STRING"
}

variable "rhino_api_key_secret_name" {
  description = "Name of the Rhino.Compute API key secret in Key Vault"
  type        = string
  default     = "COMPUTE-API-KEY"
}

variable "enable_ingress" {
  description = "Enable external ingress (set to false for internal only)"
  type        = bool
  default     = false # Internal only by default
}

variable "use_compute" {
  description = "Enable real Rhino.Compute (false = mock mode)"
  type        = bool
  default     = false
}

variable "timeout_ms" {
  description = "Default timeout for compute calls in milliseconds"
  type        = number
  default     = 240000 # 4 minutes
}

variable "compute_definitions_path" {
  description = "Path to Grasshopper definitions on Compute VM"
  type        = string
  default     = "C:\\\\compute" # Windows path with escaped backslashes
}

variable "log_level" {
  description = "Logging level (debug, info, warn, error)"
  type        = string
  default     = "info"
}
