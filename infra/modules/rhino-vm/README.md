# Rhino VM Module

Terraform module for deploying a Windows VM with Rhino.Compute for development.

## Features

- **Minimal VM Size**: Standard_B2s (2 vCPUs, 4GB RAM) - smallest suitable for Rhino
- **Cost Optimization**: Auto-shutdown at 7 PM (configurable)
- **Security**: NSG locked to your IP address only
- **OS**: Windows Server 2022 Datacenter
- **Network**: Dedicated VNet and subnet
- **Monitoring**: Boot diagnostics enabled

## Architecture

```
Your IP ──> Public IP ──> NSG (ports 3389, 80, 8081) ──> Windows VM
                                                           ├─ Rhino.Compute
                                                           └─ Auto-shutdown
```

## Cost Estimate

- **VM (Standard_B2s)**: ~$30/month (with auto-shutdown ~$20/month)
- **Public IP (Static)**: ~$3/month
- **Disk (Standard LRS)**: ~$5/month

**Total**: ~$38/month (or ~$28/month with auto-shutdown)

## Prerequisites

- Your public IP address (for NSG lockdown)
- Strong admin password for the VM
- Rhino.Compute installer (downloaded from McNeel)

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name_prefix | Prefix for resources | string | - | yes |
| resource_group_name | Resource group name | string | - | yes |
| location | Azure region | string | - | yes |
| vm_size | VM size | string | Standard_B2s | no |
| admin_username | Admin username | string | rhinoadmin | no |
| admin_password | Admin password | string | - | yes |
| allowed_source_ip | Your IP (CIDR) | string | - | yes |
| rhino_compute_port | Rhino.Compute port | number | 8081 | no |
| enable_auto_shutdown | Enable auto-shutdown | bool | true | no |
| auto_shutdown_time | Shutdown time (24h) | string | 1900 | no |

## Outputs

| Name | Description |
|------|-------------|
| public_ip_address | Public IP of the VM |
| rhino_compute_url | Rhino.Compute endpoint URL |
| rdp_connection | RDP connection command |
| admin_username | Admin username |

## Usage

### 1. Set Environment Variables

```bash
# Get your public IP
export MY_PUBLIC_IP="$(curl -s ifconfig.me)/32"

# Set a strong password
export RHINO_VM_PASSWORD="YourStrongPassword123!"
```

### 2. Deploy with Terragrunt

```bash
cd infra/live/dev/shared/rhino
terragrunt init
terragrunt plan
terragrunt apply
```

### 3. Get Connection Info

```bash
# Get public IP
terragrunt output public_ip_address

# Get RDP command
terragrunt output rdp_connection
```

### 4. Connect via RDP

```bash
# On Windows
mstsc /v:<public_ip>

# On Linux/Mac (using Remmina or xfreerdp)
xfreerdp /v:<public_ip> /u:rhinoadmin
```

### 5. Install Rhino.Compute

Once connected to the VM:

1. **Download PowerShell script from this repo**:
   ```powershell
   # In VM, download the setup script
   Invoke-WebRequest -Uri "https://github.com/.../setup-rhino.ps1" `
     -OutFile "C:\setup-rhino.ps1"
   ```

2. **Run the setup script**:
   ```powershell
   cd C:\
   .\setup-rhino.ps1
   ```

3. **Download Rhino.Compute**:
   - Get installer from McNeel website
   - Or use your organization's licensed copy
   - Extract to `C:\RhinoCompute`

4. **Start Rhino.Compute**:
   ```powershell
   cd C:\RhinoCompute
   .\compute.geometry.exe
   ```

5. **Test it works**:
   ```powershell
   # In VM
   Invoke-WebRequest -Uri "http://localhost:8081/version"
   
   # From your machine (if VM is running)
   curl http://<public_ip>:8081/version
   ```

6. **Save API Key to Key Vault**:
   ```bash
   # Get the API key from C:\rhino-api-key.txt in the VM
   # Then update Key Vault
   KV_NAME=kuduso-dev-kv-XXXXXX
   API_KEY="<key-from-vm>"
   
   az keyvault secret set \
     --vault-name $KV_NAME \
     --name COMPUTE-API-KEY \
     --value "$API_KEY"
   ```

## Security Considerations

### NSG Rules

The NSG only allows inbound traffic from your IP address:
- **Port 3389 (RDP)**: For remote management
- **Port 80 (HTTP)**: For Rhino.Compute (optional)
- **Port 8081**: For Rhino.Compute API

All other inbound traffic is denied.

### To Update Allowed IP

```bash
# If your IP changes
export MY_PUBLIC_IP="$(curl -s ifconfig.me)/32"
cd infra/live/dev/shared/rhino
terragrunt apply
```

### API Key Security

- Generated randomly by setup script
- Stored in Key Vault (not in code)
- Used by AppServer to authenticate with Rhino.Compute

## Cost Optimization

### Auto-Shutdown

VM automatically shuts down at 7 PM (configurable) to save costs.

**To start it again**:
```bash
# Via Azure CLI
az vm start --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm

# Via Azure Portal
# Navigate to VM > Start
```

### Disk Optimization

Uses Standard LRS (locally redundant storage) for cost savings. Acceptable for dev environment.

## Troubleshooting

### Can't connect via RDP

Check:
1. VM is running: `az vm show --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm --show-details --query powerState`
2. Your IP is correct: `curl ifconfig.me`
3. NSG rule matches your IP

### Rhino.Compute not responding

Check:
1. Service is running on VM
2. Windows Firewall allows port 8081
3. NSG allows your IP
4. Test locally on VM first: `Invoke-WebRequest http://localhost:8081/version`

### High costs

Enable auto-shutdown or:
```bash
# Stop VM when not in use
az vm deallocate --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm
```

## Production Considerations

For production, consider:
- **VMSS + Internal Load Balancer**: Scale horizontally
- **No public IP**: Use Azure Bastion or VPN for management
- **Managed Disks Premium**: Better performance
- **Larger VM**: Standard_D4s_v3 or larger for production workloads
- **License Management**: Rhino licensing for cloud/server use

## Cleanup

```bash
cd infra/live/dev/shared/rhino
terragrunt destroy
```

**Note**: This will permanently delete the VM and all associated resources.
