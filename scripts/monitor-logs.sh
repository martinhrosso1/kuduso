#!/bin/bash
# Log monitoring commands for Kuduso services
# Usage: Run each command in a separate terminal window for real-time monitoring

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Kuduso Log Monitoring Commands${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${GREEN}1. WORKER LOGS${NC}"
echo -e "${YELLOW}   Real-time (follow):${NC}"
echo "   az containerapp logs show \\"
echo "     --name kuduso-dev-sitefit-worker \\"
echo "     --resource-group kuduso-dev-rg \\"
echo "     --follow true \\"
echo "     --tail 50"
echo ""
echo -e "${YELLOW}   Last 100 lines:${NC}"
echo "   az containerapp logs show \\"
echo "     --name kuduso-dev-sitefit-worker \\"
echo "     --resource-group kuduso-dev-rg \\"
echo "     --follow false \\"
echo "     --tail 100"
echo ""
echo -e "${YELLOW}   Filter by job ID:${NC}"
echo "   az containerapp logs show \\"
echo "     --name kuduso-dev-sitefit-worker \\"
echo "     --resource-group kuduso-dev-rg \\"
echo "     --follow false \\"
echo "     --tail 200 \\"
echo "     --query \"[?contains(Log, 'YOUR_JOB_ID')].Log\" \\"
echo "     -o tsv"
echo ""

echo -e "${GREEN}2. APPSERVER LOGS${NC}"
echo -e "${YELLOW}   Real-time (follow):${NC}"
echo "   az containerapp logs show \\"
echo "     --name kuduso-dev-appserver \\"
echo "     --resource-group kuduso-dev-rg \\"
echo "     --follow true \\"
echo "     --tail 50"
echo ""
echo -e "${YELLOW}   Last 100 lines:${NC}"
echo "   az containerapp logs show \\"
echo "     --name kuduso-dev-appserver \\"
echo "     --resource-group kuduso-dev-rg \\"
echo "     --follow false \\"
echo "     --tail 100"
echo ""
echo -e "${YELLOW}   Filter by correlation ID:${NC}"
echo "   az containerapp logs show \\"
echo "     --name kuduso-dev-appserver \\"
echo "     --resource-group kuduso-dev-rg \\"
echo "     --follow false \\"
echo "     --tail 200 \\"
echo "     --query \"[?contains(Log, 'YOUR_CORRELATION_ID')].Log\" \\"
echo "     -o tsv"
echo ""
echo -e "${YELLOW}   Show only errors:${NC}"
echo "   az containerapp logs show \\"
echo "     --name kuduso-dev-appserver \\"
echo "     --resource-group kuduso-dev-rg \\"
echo "     --follow false \\"
echo "     --tail 200 | grep -i error"
echo ""

echo -e "${GREEN}3. API LOGS${NC}"
echo -e "${YELLOW}   Real-time (follow):${NC}"
echo "   az containerapp logs show \\"
echo "     --name kuduso-dev-sitefit-api \\"
echo "     --resource-group kuduso-dev-rg \\"
echo "     --follow true \\"
echo "     --tail 50"
echo ""
echo -e "${YELLOW}   Last 100 lines:${NC}"
echo "   az containerapp logs show \\"
echo "     --name kuduso-dev-sitefit-api \\"
echo "     --resource-group kuduso-dev-rg \\"
echo "     --follow false \\"
echo "     --tail 100"
echo ""

echo -e "${GREEN}4. RHINO VM LOGS${NC}"
echo -e "${YELLOW}   Check Rhino.Compute process:${NC}"
echo "   az vm run-command invoke \\"
echo "     --name kuduso-dev-rhino-vm \\"
echo "     --resource-group kuduso-dev-rg \\"
echo "     --command-id RunPowerShellScript \\"
echo "     --scripts 'Get-Process | Where-Object { \$_.ProcessName -like \"*compute*\" -or \$_.ProcessName -like \"*rhino*\" } | Select-Object Id, ProcessName, CPU, WorkingSet'"
echo ""
echo -e "${YELLOW}   Check recent Windows Event Logs (Application):${NC}"
echo "   az vm run-command invoke \\"
echo "     --name kuduso-dev-rhino-vm \\"
echo "     --resource-group kuduso-dev-rg \\"
echo "     --command-id RunPowerShellScript \\"
echo "     --scripts 'Get-EventLog -LogName Application -Newest 20 | Where-Object { \$_.Source -like \"*Rhino*\" -or \$_.Source -like \"*IIS*\" } | Format-Table TimeGenerated, EntryType, Source, Message -AutoSize'"
echo ""
echo -e "${YELLOW}   Check compute.geometry.exe logs (if exists):${NC}"
echo "   az vm run-command invoke \\"
echo "     --name kuduso-dev-rhino-vm \\"
echo "     --resource-group kuduso-dev-rg \\"
echo "     --command-id RunPowerShellScript \\"
echo "     --scripts 'if (Test-Path \"C:\\inetpub\\compute\\logs\") { Get-ChildItem \"C:\\inetpub\\compute\\logs\" -Filter *.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content -Tail 50 }'"
echo ""
echo -e "${YELLOW}   Check IIS logs:${NC}"
echo "   az vm run-command invoke \\"
echo "     --name kuduso-dev-rhino-vm \\"
echo "     --resource-group kuduso-dev-rg \\"
echo "     --command-id RunPowerShellScript \\"
echo "     --scripts 'Get-ChildItem \"C:\\Windows\\System32\\LogFiles\\HTTPERR\" -Filter *.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content -Tail 20'"
echo ""

echo -e "${GREEN}5. COMBINED MONITORING (Multi-Terminal Setup)${NC}"
echo -e "${YELLOW}   Terminal 1 - Worker:${NC}"
echo "   watch -n 2 'az containerapp logs show --name kuduso-dev-sitefit-worker --resource-group kuduso-dev-rg --follow false --tail 30 | tail -30'"
echo ""
echo -e "${YELLOW}   Terminal 2 - AppServer:${NC}"
echo "   watch -n 2 'az containerapp logs show --name kuduso-dev-appserver --resource-group kuduso-dev-rg --follow false --tail 30 | tail -30'"
echo ""
echo -e "${YELLOW}   Terminal 3 - Test job submission:${NC}"
echo "   # Use for testing"
echo ""

echo -e "${GREEN}6. QUICK LOG CHECKS${NC}"
echo -e "${YELLOW}   Check last error in each service:${NC}"
echo "   # Worker"
echo "   az containerapp logs show --name kuduso-dev-sitefit-worker --resource-group kuduso-dev-rg --tail 100 | grep -i error | tail -5"
echo ""
echo "   # AppServer"
echo "   az containerapp logs show --name kuduso-dev-appserver --resource-group kuduso-dev-rg --tail 100 | grep -i error | tail -5"
echo ""
echo "   # API"
echo "   az containerapp logs show --name kuduso-dev-sitefit-api --resource-group kuduso-dev-rg --tail 100 | grep -i error | tail -5"
echo ""

echo -e "${GREEN}7. STRUCTURED LOG PARSING${NC}"
echo -e "${YELLOW}   Parse JSON logs from AppServer:${NC}"
cat << 'PARSER'
az containerapp logs show \
  --name kuduso-dev-appserver \
  --resource-group kuduso-dev-rg \
  --tail 100 \
  -o tsv 2>/dev/null | \
python3 << 'PYEOF'
import sys
import json

for line in sys.stdin:
    try:
        if '{"level"' in line:
            # Extract JSON from log line
            start = line.index('{"level"')
            log_json = json.loads(line[start:])
            
            level = log_json.get('level', 'INFO').upper()
            event = log_json.get('event', 'unknown')
            timestamp = log_json.get('timestamp', '')[:23]  # Trim to ms
            cid = log_json.get('cid', 'N/A')[:8]  # First 8 chars
            
            # Color coding
            color = '\033[91m' if level == 'ERROR' else '\033[93m' if level == 'WARN' else '\033[92m'
            reset = '\033[0m'
            
            print(f"{timestamp} | {color}{level:5}{reset} | {cid} | {event}")
            
            # Print error details
            if level == 'ERROR' and 'error' in log_json:
                print(f"  → Error: {log_json['error']}")
                if 'details' in log_json:
                    print(f"  → Details: {log_json['details']}")
    except:
        continue
PYEOF
PARSER
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}TIP:${NC} Run commands in separate terminals for parallel monitoring"
echo -e "${YELLOW}TIP:${NC} Use Ctrl+C to stop following logs"
echo -e "${YELLOW}TIP:${NC} Add 2>&1 at the end to capture stderr"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

