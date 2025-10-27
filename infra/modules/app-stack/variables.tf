# Variables for app-stack module (sitefit app infrastructure)

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "app_name" {
  description = "Application name (e.g., 'sitefit')"
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

variable "servicebus_namespace_id" {
  description = "ID of the Service Bus namespace"
  type        = string
}

variable "key_vault_id" {
  description = "ID of the Key Vault"
  type        = string
}

variable "key_vault_uri" {
  description = "URI of the Key Vault"
  type        = string
}

variable "appserver_url" {
  description = "Internal URL of the shared AppServer"
  type        = string
  default     = "http://kuduso-dev-appserver:8080"
}

# API Container App Configuration
variable "api_image" {
  description = "Container image for API (e.g., 'api-node:latest')"
  type        = string
  default     = "api-node:latest"
}

variable "api_cpu" {
  description = "CPU allocation for API"
  type        = string
  default     = "0.5"
}

variable "api_memory" {
  description = "Memory allocation for API"
  type        = string
  default     = "1Gi"
}

variable "api_min_replicas" {
  description = "Minimum replicas for API"
  type        = number
  default     = 1
}

variable "api_max_replicas" {
  description = "Maximum replicas for API"
  type        = number
  default     = 5
}

variable "api_port" {
  description = "API container port"
  type        = number
  default     = 3000
}

# Worker Container App Configuration
variable "worker_image" {
  description = "Container image for Worker (e.g., 'worker-node:latest')"
  type        = string
  default     = "worker-node:latest"
}

variable "worker_cpu" {
  description = "CPU allocation for Worker"
  type        = string
  default     = "0.5"
}

variable "worker_memory" {
  description = "Memory allocation for Worker"
  type        = string
  default     = "1Gi"
}

variable "worker_min_replicas" {
  description = "Minimum replicas for Worker (0 for scale-to-zero)"
  type        = number
  default     = 0
}

variable "worker_max_replicas" {
  description = "Maximum replicas for Worker"
  type        = number
  default     = 10
}

variable "worker_port" {
  description = "Worker container port"
  type        = number
  default     = 8080
}

# KEDA Configuration
variable "keda_queue_length" {
  description = "Queue length threshold for KEDA scaling"
  type        = number
  default     = 5
}

variable "keda_polling_interval" {
  description = "KEDA polling interval in seconds"
  type        = number
  default     = 30
}

variable "keda_cooldown_period" {
  description = "KEDA cooldown period in seconds"
  type        = number
  default     = 300
}

# Secret Names
variable "database_url_secret_name" {
  description = "Name of the database URL secret in Key Vault"
  type        = string
  default     = "DATABASE-URL"
}

variable "servicebus_connection_secret_name" {
  description = "Name of the Service Bus connection secret in Key Vault"
  type        = string
  default     = "SERVICEBUS-CONN"
}
