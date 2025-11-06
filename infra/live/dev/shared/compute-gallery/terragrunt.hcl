# Terragrunt configuration for Compute Gallery in dev environment

# Include root configuration
include "root" {
  path = find_in_parent_folders()
}

# Dependency on shared-core
dependency "core" {
  config_path = "../core"
  
  mock_outputs = {
    resource_group_name = "mock-rg"
    location            = "westeurope"
  }
}

# Point to the compute-gallery module
terraform {
  source = "../../../../modules/compute-gallery"
}

# Module inputs
inputs = {
  gallery_name        = "kuduso_images"
  resource_group_name = dependency.core.outputs.resource_group_name
  location            = dependency.core.outputs.location
  
  # Reference the existing managed image that was created manually
  source_image_name = "rhino-compute-image-v1"
  
  # Version of the image to create in the gallery
  image_version = "1.0.0"
  
  # Optional: replicate to additional regions
  additional_regions = []
}
