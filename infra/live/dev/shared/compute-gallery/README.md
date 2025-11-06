# Compute Gallery Deployment - Dev Environment

## Quick Start

Deploy the Compute Gallery to manage custom Rhino.Compute images:

```bash
cd infra/live/dev/shared/compute-gallery
terragrunt apply
```

## What This Deploys

This configuration:
- ✅ Creates an Azure Compute Gallery named `kuduso_images`
- ✅ Defines a Rhino.Compute image specification
- ✅ Creates version `1.0.0` from the existing managed image `rhino-compute-image-v1`
- ✅ Makes the image available for VM deployment

## Dependencies

This module depends on:
- `../core` - For resource group and location

## Post-Deployment

After the gallery is deployed:

1. **Deploy Rhino VMs** using the custom image:
   ```bash
   cd ../rhino
   terragrunt apply
   ```

2. **Verify the image** is available:
   ```bash
   az sig image-version list \
     --resource-group kuduso-dev-rg \
     --gallery-name kuduso_images \
     --gallery-image-definition rhino-compute \
     --output table
   ```

## Customization

Edit `terragrunt.hcl` to customize:

### Use a Different Source Image
```hcl
inputs = {
  source_image_name = "rhino-compute-image-v2"
  image_version     = "2.0.0"
}
```

### Replicate to Additional Regions
```hcl
inputs = {
  additional_regions = ["northeurope", "uksouth"]
}
```

## Workflow: Creating a New Image Version

When you need to update the image (e.g., Rhino updates, configuration changes):

1. **Deploy a VM** from current image:
   ```bash
   cd ../rhino
   terragrunt apply
   ```

2. **Make changes** via RDP (install updates, modify config, etc.)

3. **Test thoroughly** to ensure everything works

4. **Sysprep** the VM:
   ```powershell
   # On the VM via RDP
   C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
   ```

5. **Capture** as managed image:
   ```bash
   az vm deallocate -g kuduso-dev-rg -n kuduso-dev-rhino-vm
   az vm generalize -g kuduso-dev-rg -n kuduso-dev-rhino-vm
   az image create \
     -g kuduso-dev-rg \
     -n rhino-compute-image-v2 \
     --source kuduso-dev-rhino-vm
   ```

6. **Update** `terragrunt.hcl`:
   ```hcl
   inputs = {
     source_image_name = "rhino-compute-image-v2"
     image_version     = "2.0.0"
   }
   ```

7. **Deploy** new version:
   ```bash
   terragrunt apply
   ```

## Troubleshooting

### Image not found
```
Error: could not find image "rhino-compute-image-v1"
```

**Solution**: Verify the managed image exists:
```bash
az image show \
  --resource-group kuduso-dev-rg \
  --name rhino-compute-image-v1
```

### Permission denied
```
Error: authorization failed
```

**Solution**: Ensure you're logged in:
```bash
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

## Clean Up

To delete the gallery (⚠️ destroys all image versions):
```bash
terragrunt destroy
```

Note: This will NOT delete the source managed images.
