# Outputs for rhino-vm module

output "vm_id" {
  description = "ID of the Rhino VM"
  value       = azurerm_windows_virtual_machine.main.id
}

output "vm_name" {
  description = "Name of the Rhino VM"
  value       = azurerm_windows_virtual_machine.main.name
}

output "public_ip_address" {
  description = "Public IP address of the Rhino VM"
  value       = azurerm_public_ip.main.ip_address
}

output "public_ip_fqdn" {
  description = "FQDN of the public IP (if configured)"
  value       = azurerm_public_ip.main.fqdn
}

output "private_ip_address" {
  description = "Private IP address of the Rhino VM"
  value       = azurerm_network_interface.main.private_ip_address
}

output "rhino_compute_url" {
  description = "URL for Rhino.Compute endpoint"
  value       = "http://${azurerm_public_ip.main.ip_address}:${var.rhino_compute_port}/"
}

output "rdp_connection" {
  description = "RDP connection command"
  value       = "mstsc /v:${azurerm_public_ip.main.ip_address}"
}

output "admin_username" {
  description = "Admin username for the VM"
  value       = var.admin_username
}

output "nsg_id" {
  description = "ID of the Network Security Group"
  value       = azurerm_network_security_group.main.id
}
