# Rhino.Compute Custom Image - Terraform Setup

## Overview

Your Rhino VM infrastructure has been updated to use a **custom image** stored in Azure Compute Gallery. This enables:

✅ **Fast deployment** - Deploy pre-configured VMs in minutes  
✅ **Consistency** - Every VM uses the identical configuration  
✅ **Scalability** - Easy to create VM clusters or scale sets  
✅ **Version control** - Track and manage image versions

---

## 🏗️ **What Changed**

### New Module: `compute-gallery`
Location: `infra/modules/compute-gallery/`

Creates and manages:
- Azure Compute Gallery
- Image definition for Rhino.Compute
- Image versions from your managed images

### Updated Module: `rhino-vm`
Location: `infra/modules/rhino-vm/`

Changes:
- ✅ Now uses custom image from Compute Gallery
- ❌ Removed custom script extension
- ❌ Removed blob storage script upload

**Before:**
```hcl
source_image_reference {
  publisher = "MicrosoftWindowsServer"
  offer     = "WindowsServer"
  sku       = "2022-datacenter"
  version   = "latest"
}
```

**After:**
```hcl
source_image_id = var.source_image_id  # From Compute Gallery
```

### New Configuration: `live/dev/shared/compute-gallery/`
Terragrunt configuration to deploy the Compute Gallery in dev environment.

### Updated Configuration: `live/dev/shared/rhino/`
Now depends on `compute-gallery` and uses the custom image.

---

## 📦 **Your Current Image**

You already created the managed image:

```json
{
  "name": "rhino-compute-image-v1",
  "id": "/subscriptions/0574d5fa-29ba-4262-8893-a08d22a66552/resourceGroups/kuduso-dev-rg/providers/Microsoft.Compute/images/rhino-compute-image-v1",
  "location": "westeurope",
  "resourceGroup": "kuduso-dev-rg",
  "osState": "Generalized"
}
```

This image includes:
- ✅ Windows Server 2022 Datacenter
- ✅ Rhino 8 (licensed)
- ✅ Rhino.Compute (built and configured)
- ✅ IIS with proper app pool settings
- ✅ All dependencies (.NET, ASP.NET Core Module, etc.)

---

## 🚀 **Deployment Steps**

### Step 1: Deploy Compute Gallery

```bash
cd infra/live/dev/shared/compute-gallery
terragrunt apply
```

**What this does:**
1. Creates gallery: `kuduso_images`
2. Creates image definition: `rhino-compute`
3. Creates version `1.0.0` from `rhino-compute-image-v1`

**Expected output:**
```
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:
gallery_id = "/subscriptions/.../kuduso_images"
image_version_id = "/subscriptions/.../kudoso_images/images/rhino-compute/versions/1.0.0"
```

---

### Step 2: Deploy Rhino VM from Custom Image

```bash
cd ../rhino
terragrunt apply
```

**What this does:**
1. Deploys VM using custom image from gallery
2. VM boots with Rhino.Compute pre-installed
3. Ready to use in ~5 minutes (vs 30+ minutes before)

**Post-deployment:** Set API key and restart IIS:
```powershell
# Via RDP or Azure Run Command
[System.Environment]::SetEnvironmentVariable(
    'RHINO_COMPUTE_KEY',
    'YOUR_KEY_FROM_KEYVAULT',
    'Machine'
)
iisreset /restart
```

---

## 📁 **File Structure**

```
infra/
├── modules/
│   ├── compute-gallery/          # NEW
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   └── rhino-vm/                  # UPDATED
│       ├── main.tf                # Uses custom image
│       ├── variables.tf           # source_image_id added
│       └── outputs.tf
└── live/dev/shared/
    ├── compute-gallery/           # NEW
    │   ├── terragrunt.hcl
    │   └── README.md
    └── rhino/                     # UPDATED
        └── terragrunt.hcl         # References gallery image
```

---

## 🔄 **Workflow: Creating New Image Versions**

When you need to update the image:

### 1. Deploy VM from Current Image
```bash
cd infra/live/dev/shared/rhino
terragrunt apply
```

### 2. Make Changes
- RDP to the VM
- Install Rhino updates
- Modify Rhino.Compute configuration
- Test thoroughly

### 3. Sysprep (Generalize)
```powershell
# On the VM via RDP
C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
```
⚠️ VM will shut down and become a template

### 4. Capture New Image
```bash
RESOURCE_GROUP="kuduso-dev-rg"
VM_NAME="kuduso-dev-rhino-vm"
NEW_IMAGE="rhino-compute-image-v2"

az vm deallocate -g $RESOURCE_GROUP -n $VM_NAME
az vm generalize -g $RESOURCE_GROUP -n $VM_NAME
az image create \
  -g $RESOURCE_GROUP \
  -n $NEW_IMAGE \
  --source $VM_NAME
```

### 5. Update Terragrunt Config
Edit `infra/live/dev/shared/compute-gallery/terragrunt.hcl`:
```hcl
inputs = {
  source_image_name = "rhino-compute-image-v2"  # Changed
  image_version     = "2.0.0"                    # Changed
}
```

### 6. Deploy New Version
```bash
cd infra/live/dev/shared/compute-gallery
terragrunt apply
```

### 7. Deploy VMs with New Version
```bash
cd ../rhino
terragrunt destroy  # Delete old VM
terragrunt apply    # Create VM with v2.0.0
```

---

## 🎯 **Benefits Over Previous Setup**

| Aspect | Before (Script-based) | After (Custom Image) |
|--------|----------------------|---------------------|
| **Deployment Time** | 30-45 minutes | 5-10 minutes |
| **Consistency** | Scripts could fail | Guaranteed identical |
| **Scaling** | Manual for each VM | Deploy 10 VMs in minutes |
| **Rhino Licensing** | Manual per VM | Pre-licensed in image |
| **Dependencies** | Install on every deploy | Baked into image |
| **Testing** | Test every deployment | Test once, deploy many |

---

## 📊 **Terraform Dependency Graph**

```
shared-core
    ↓
compute-gallery ← (depends on managed image)
    ↓
rhino-vm (depends on gallery image)
```

---

## 🛠️ **VM Scale Set (Future)**

To create an auto-scaling cluster:

### 1. Create Scale Set Module
```hcl
# infra/modules/rhino-vmss/main.tf
resource "azurerm_windows_virtual_machine_scale_set" "rhino" {
  source_image_id = var.source_image_id  # From gallery
  instances       = 2
  # ... auto-scaling configuration
}
```

### 2. Deploy Scale Set
```bash
cd infra/live/dev/shared/rhino-cluster
terragrunt apply
```

### 3. Result
- **2-10 VMs** auto-scaling based on load
- **Load balancer** distributing requests
- **Health probes** on `/version` endpoint
- **All VMs identical** from custom image

---

## 🔐 **Security Notes**

### API Key Management
- **Not stored in image** (cleared by sysprep)
- **Must be set after deployment** via:
  - Azure Run Command (automated)
  - RDP (manual)
  - Custom Script Extension (optional)

### Rhino Licensing
- **License IS in image** (if activated before sysprep)
- For clusters: Use **Rhino Cloud Zoo** for flexible licensing
- Or purchase multiple licenses

---

## 📚 **Documentation**

- **Module README**: `infra/modules/compute-gallery/README.md`
- **Deployment Guide**: `infra/live/dev/shared/compute-gallery/README.md`
- **Setup Scripts**: `scripts/rhino-setup/` (still useful for initial image creation)

---

## ✅ **Verification**

After deployment, verify:

### Check Gallery Image
```bash
az sig image-version show \
  -g kuduso-dev-rg \
  --gallery-name kuduso_images \
  --gallery-image-definition rhino-compute \
  --gallery-image-version 1.0.0
```

### Check VM is Using Custom Image
```bash
az vm show \
  -g kuduso-dev-rg \
  -n kuduso-dev-rhino-vm \
  --query "storageProfile.imageReference.id" -o tsv
```

Should output:
```
/subscriptions/.../galleries/kuduso_images/images/rhino-compute/versions/1.0.0
```

### Test Rhino.Compute
```bash
curl http://VM_PUBLIC_IP:8081/version
```

Should return:
```json
{
  "rhino": "8.24.25281.15001",
  "compute": "8.0.0.0"
}
```

---

## 🎉 **You're Ready!**

Your infrastructure is now set up to:
- ✅ Deploy pre-configured Rhino.Compute VMs in minutes
- ✅ Scale to multiple VMs or VM Scale Sets easily
- ✅ Maintain consistent configuration across all instances
- ✅ Version and track your VM images over time

**Next:** Deploy the gallery and test deploying a VM from the custom image!
