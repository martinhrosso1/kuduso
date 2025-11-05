# Variables for rhino-vm module

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

variable "vm_size" {
  description = "Size of the VM"
  type        = string
  default     = "Standard_B2s" # Smallest suitable: 2 vCPUs, 4GB RAM
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "rhinoadmin"
}

variable "admin_password" {
  description = "Admin password for the VM (use strong password)"
  type        = string
  sensitive   = true
}

variable "allowed_source_ip" {
  description = "Your public IP address (CIDR format, e.g., '1.2.3.4/32')"
  type        = string
}

variable "rhino_compute_port" {
  description = "Port for Rhino.Compute"
  type        = number
  default     = 8081
}

variable "enable_auto_shutdown" {
  description = "Enable auto-shutdown at night to save costs"
  type        = bool
  default     = true
}

variable "auto_shutdown_time" {
  description = "Auto-shutdown time (24h format, e.g., '1900' for 7 PM)"
  type        = string
  default     = "1900"
}

variable "auto_shutdown_timezone" {
  description = "Timezone for auto-shutdown"
  type        = string
  default     = "Central Europe Standard Time"
}

variable "key_vault_id" {
  description = "ID of the Key Vault to grant access to"
  type        = string
}

variable "setup_script_content" {
  description = "Content of the automated setup PowerShell script"
  type        = string
}

variable "storage_account_name" {
  description = "Name of the storage account for script uploads"
  type        = string
}

variable "storage_account_key" {
  description = "Primary access key for the storage account"
  type        = string
  sensitive   = true
}

variable "vm_scripts_container_name" {
  description = "Name of the storage container for VM scripts"
  type        = string
}
