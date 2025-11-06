# Variables for compute-gallery module

variable "gallery_name" {
  description = "Name of the Compute Gallery (alphanumeric, periods, and underscores only)"
  type        = string
  default     = "kuduso_images"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for the gallery"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "source_image_name" {
  description = "Name of the existing managed image to import"
  type        = string
  default     = "rhino-compute-image-v1"
}

variable "image_version" {
  description = "Version number for the gallery image (e.g., 1.0.0)"
  type        = string
  default     = "1.0.0"
}

variable "additional_regions" {
  description = "Additional regions to replicate the image to"
  type        = list(string)
  default     = []
}
