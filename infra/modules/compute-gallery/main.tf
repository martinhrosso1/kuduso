# Compute Gallery module: Manages custom VM images for Rhino.Compute

locals {
  tags = merge(
    var.common_tags,
    {
      module  = "compute-gallery"
      purpose = "custom-images"
    }
  )
}

# Azure Compute Gallery
resource "azurerm_shared_image_gallery" "main" {
  name                = var.gallery_name
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = "Custom VM images for Kuduso infrastructure"
  
  tags = local.tags
}

# Image Definition - Rhino.Compute
resource "azurerm_shared_image" "rhino_compute" {
  name                = "rhino-compute"
  gallery_name        = azurerm_shared_image_gallery.main.name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Windows"
  hyper_v_generation  = "V1"
  
  identifier {
    publisher = "Kuduso"
    offer     = "RhinoCompute"
    sku       = "2022-datacenter-rhino8"
  }
  
  description = "Windows Server 2022 with Rhino 8 and Rhino.Compute pre-configured"
  
  tags = local.tags
}

# Data source to reference existing managed image
data "azurerm_image" "rhino_compute_source" {
  name                = var.source_image_name
  resource_group_name = var.resource_group_name
}

# Image Version - Created from existing managed image
resource "azurerm_shared_image_version" "rhino_compute_v1" {
  name                = var.image_version
  gallery_name        = azurerm_shared_image_gallery.main.name
  image_name          = azurerm_shared_image.rhino_compute.name
  resource_group_name = var.resource_group_name
  location            = var.location
  
  # Reference the existing managed image
  managed_image_id = data.azurerm_image.rhino_compute_source.id
  
  target_region {
    name                   = var.location
    regional_replica_count = 1
    storage_account_type   = "Standard_LRS"
  }
  
  # Optional: Add more regions for replication
  dynamic "target_region" {
    for_each = var.additional_regions
    content {
      name                   = target_region.value
      regional_replica_count = 1
      storage_account_type   = "Standard_LRS"
    }
  }
  
  tags = local.tags
  
  lifecycle {
    ignore_changes = [
      # Ignore changes to managed_image_id to prevent recreation
      # when the source image is updated manually
      managed_image_id
    ]
  }
}
