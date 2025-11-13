#!/bin/bash
# Upload Grasshopper definition to Rhino VM via RDP folder sharing

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SOURCE_DIR="/home/martin/Desktop/kuduso/contracts/sitefit/1.0.0"
SOURCE_FILE="$SOURCE_DIR/sitefit_ready.ghx"
VM_IP=$(az vm show --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm --show-details --query "publicIps" -o tsv)

echo -e "${BLUE}Upload GHX to Rhino VM${NC}"
echo ""
echo -e "${YELLOW}1. Connecting to VM with folder sharing...${NC}"
echo "VM IP: $VM_IP"
echo "Shared folder: $SOURCE_DIR"
echo ""

# Connect via RDP with folder sharing
xfreerdp /v:$VM_IP /u:rhinoadmin \
  /dynamic-resolution /cert:ignore \
  /drive:local,$SOURCE_DIR &

sleep 3

echo ""
echo -e "${YELLOW}2. Run this in VM PowerShell:${NC}"
echo ""
echo -e "${GREEN}New-Item -ItemType Directory -Path 'C:\compute\sitefit\1.0.0' -Force${NC}"
echo -e "${GREEN}Copy-Item '\\\\tsclient\\local\\sitefit_ready.ghx' -Destination 'C:\compute\sitefit\1.0.0\ghlogic.ghx'${NC}"
echo -e "${GREEN}Get-Item 'C:\compute\sitefit\1.0.0\ghlogic.ghx' | Format-List Length, LastWriteTime${NC}"
echo ""

