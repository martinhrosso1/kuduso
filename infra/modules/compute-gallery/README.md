# Compute Gallery Module

This module manages Azure Compute Gallery for storing and distributing custom VM images.

## Purpose

The Compute Gallery stores pre-configured Rhino.Compute VM images that include:
- Windows Server 2022 Datacenter
- Rhino 8 (licensed)
- Rhino.Compute (built and configured)
- IIS with proper app pool settings
- All dependencies (.NET, ASP.NET Core Module, etc.)

## Prerequisites

Before deploying this module, you must have:

1. **A generalized managed image** created from a configured VM
2. The image must exist in the same resource group

## Creating the Source Image

### Manual Process (One-Time Setup)

1. **Deploy and configure a base VM** using the `rhino-vm` module (without custom image)
2. **RDP to the VM** and run all setup scripts (01-10)
3. **Test thoroughly** to ensure Rhino.Compute works correctly
4. **Generalize the VM** (makes it a template):
   ```powershell
   # On the VM via RDP
   C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
   ```
   ⚠️ **Warning**: After sysprep, don't start this VM directly - it becomes a template

5. **Capture the image** using Azure CLI:
   ```bash
   # Set variables
   RESOURCE_GROUP="kuduso-dev-rg"
   VM_NAME="kuduso-dev-rhino-vm"
   IMAGE_NAME="rhino-compute-image-v1"
   
   # Stop and deallocate (if not already shutdown by sysprep)
   az vm deallocate --resource-group $RESOURCE_GROUP --name $VM_NAME
   
   # Mark as generalized
   az vm generalize --resource-group $RESOURCE_GROUP --name $VM_NAME
   
   # Create managed image
   az image create \
     --resource-group $RESOURCE_GROUP \
     --name $IMAGE_NAME \
     --source $VM_NAME
   ```

6. **Deploy this Terraform module** to add the image to the gallery

## Usage

### Deploy the Gallery

```bash
cd infra/live/dev/shared/compute-gallery
terragrunt apply
```

This will:
1. Create the Compute Gallery
2. Create an image definition for Rhino.Compute
3. Create version 1.0.0 from the existing managed image

### Deploy VMs from the Image

Once the gallery is created, the `rhino-vm` module will automatically use the custom image:

```bash
cd infra/live/dev/shared/rhino
terragrunt apply
```

New VMs will be deployed with Rhino.Compute pre-configured!

## Post-Deployment Steps

After deploying a VM from the custom image:

1. **Set the RHINO_COMPUTE_KEY** via Azure Run Command or RDP:
   ```powershell
   [System.Environment]::SetEnvironmentVariable(
       'RHINO_COMPUTE_KEY', 
       'YOUR_KEY_FROM_KEYVAULT',
       'Machine'
   )
   ```

2. **Restart IIS**:
   ```powershell
   iisreset /restart
   ```

3. **Test the endpoint**:
   ```powershell
   curl http://VM_PUBLIC_IP:8081/version
   ```

## Updating the Image

To create a new version (e.g., after Rhino updates):

1. Deploy a VM from the current gallery image
2. Make your updates (install Rhino updates, modify configuration, etc.)
3. Test thoroughly
4. Sysprep and capture as a new managed image (e.g., `rhino-compute-image-v2`)
5. Update the `source_image_name` variable to the new image name
6. Update the `image_version` variable (e.g., `2.0.0`)
7. Run `terragrunt apply`

## Outputs

- `gallery_id` - ID of the Compute Gallery
- `gallery_name` - Name of the gallery
- `image_definition_id` - ID of the Rhino.Compute image definition
- `image_version_id` - ID of the image version (used by `rhino-vm` module)
- `image_version_name` - Version number of the image

## Module Variables

| Name | Description | Default |
|------|-------------|---------|
| `gallery_name` | Name of the Compute Gallery | `kuduso_images` |
| `resource_group_name` | Resource group name | Required |
| `location` | Azure region | Required |
| `source_image_name` | Name of existing managed image | `rhino-compute-image-v1` |
| `image_version` | Version number for gallery image | `1.0.0` |
| `additional_regions` | Additional regions to replicate to | `[]` |

## Architecture

```
┌─────────────────────────────────────────────┐
│ Compute Gallery                             │
│  └─ rhino-compute (Image Definition)        │
│      └─ 1.0.0 (Image Version)               │
│          ← References: rhino-compute-image-v1│
└─────────────────────────────────────────────┘
                    ↓
         Used by rhino-vm module
                    ↓
┌─────────────────────────────────────────────┐
│ VM Deployment                               │
│  - Pre-configured with Rhino.Compute        │
│  - Ready to serve requests (after API key)  │
└─────────────────────────────────────────────┘
```

## Benefits

✅ **Fast deployment** - VMs deploy in minutes instead of hours  
✅ **Consistency** - All VMs use identical configuration  
✅ **Scaling** - Easy to deploy multiple VMs or VM Scale Sets  
✅ **Version control** - Track image versions over time  
✅ **Multi-region** - Replicate images to multiple regions
