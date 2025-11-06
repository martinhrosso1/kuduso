# Outputs for compute-gallery module

output "gallery_id" {
  description = "ID of the Compute Gallery"
  value       = azurerm_shared_image_gallery.main.id
}

output "gallery_name" {
  description = "Name of the Compute Gallery"
  value       = azurerm_shared_image_gallery.main.name
}

output "image_definition_id" {
  description = "ID of the Rhino Compute image definition"
  value       = azurerm_shared_image.rhino_compute.id
}

output "image_version_id" {
  description = "ID of the latest Rhino Compute image version"
  value       = azurerm_shared_image_version.rhino_compute_v1.id
}

output "image_version_name" {
  description = "Version number of the image"
  value       = azurerm_shared_image_version.rhino_compute_v1.name
}
