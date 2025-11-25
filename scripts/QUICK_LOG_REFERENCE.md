# Quick Log Monitoring Reference

## 🚀 Most Used Commands

### Follow Logs in Real-Time

**Worker (in Terminal 1):**
```bash
az containerapp logs show \
  --name kuduso-dev-sitefit-worker \
  --resource-group kuduso-dev-rg \
  --follow true \
  --tail 50
```

**AppServer (in Terminal 2):**
```bash
az containerapp logs show \
  --name kuduso-dev-appserver \
  --resource-group kuduso-dev-rg \
  --follow true \
  --tail 50
```

**API (in Terminal 3):**
```bash
az containerapp logs show \
  --name kuduso-dev-sitefit-api \
  --resource-group kuduso-dev-rg \
  --follow true \
  --tail 50
```

---

## 🔍 Search Logs by ID

**By Job ID:**
```bash
JOB_ID="your-job-id-here"
az containerapp logs show \
  --name kuduso-dev-sitefit-worker \
  --resource-group kuduso-dev-rg \
  --tail 200 | grep $JOB_ID
```

**By Correlation ID (AppServer):**
```bash
CID="your-correlation-id-here"
az containerapp logs show \
  --name kuduso-dev-appserver \
  --resource-group kuduso-dev-rg \
  --tail 200 | grep $CID
```

---

## 🔴 Show Only Errors

**Worker errors:**
```bash
az containerapp logs show \
  --name kuduso-dev-sitefit-worker \
  --resource-group kuduso-dev-rg \
  --tail 100 | grep -i error
```

**AppServer errors:**
```bash
az containerapp logs show \
  --name kuduso-dev-appserver \
  --resource-group kuduso-dev-rg \
  --tail 100 | grep -i error
```

---

## 🖥️ Rhino VM Logs

**Check running processes:**
```bash
az vm run-command invoke \
  --name kuduso-dev-rhino-vm \
  --resource-group kuduso-dev-rg \
  --command-id RunPowerShellScript \
  --scripts 'Get-Process | Where-Object { $_.ProcessName -like "*compute*" -or $_.ProcessName -like "*rhino*" } | Select-Object Id, ProcessName, CPU'
```

**Check HTTP.SYS error logs:**
```bash
az vm run-command invoke \
  --name kuduso-dev-rhino-vm \
  --resource-group kuduso-dev-rg \
  --command-id RunPowerShellScript \
  --scripts 'Get-ChildItem "C:\Windows\System32\LogFiles\HTTPERR" -Filter *.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content -Tail 20'
```

**Check if GHX file exists:**
```bash
az vm run-command invoke \
  --name kuduso-dev-rhino-vm \
  --resource-group kuduso-dev-rg \
  --command-id RunPowerShellScript \
  --scripts 'Test-Path "C:\compute\sitefit\1.1.0\ghlogic.ghx"; if (Test-Path "C:\compute\sitefit\1.1.0\ghlogic.ghx") { (Get-Item "C:\compute\sitefit\1.1.0\ghlogic.ghx").Length }'
```

---

## 📊 Parsed/Structured Logs

**Pretty-print AppServer JSON logs:**
```bash
az containerapp logs show \
  --name kuduso-dev-appserver \
  --resource-group kuduso-dev-rg \
  --tail 50 | grep -o '{"level".*' | while read line; do echo "$line" | python3 -m json.tool 2>/dev/null || echo "$line"; done
```

**Extract only events:**
```bash
az containerapp logs show \
  --name kuduso-dev-appserver \
  --resource-group kudoso-dev-rg \
  --tail 100 | grep -o '{"level".*' | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        data = json.loads(line.strip())
        print(f\"{data.get('timestamp', '')[:19]} | {data.get('event', 'N/A'):40} | {data.get('level', 'INFO'):5}\")
    except: pass
"
```

---

## 🧪 Testing Workflow

### Terminal Setup

**Terminal 1 - Worker logs:**
```bash
az containerapp logs show --name kuduso-dev-sitefit-worker --resource-group kuduso-dev-rg --follow true --tail 20
```

**Terminal 2 - AppServer logs:**
```bash
az containerapp logs show --name kuduso-dev-appserver --resource-group kuduso-dev-rg --follow true --tail 20
```

**Terminal 3 - Submit test job:**
```bash
cd /home/martin/Desktop/kuduso/contracts/sitefit/1.1.0
./test-v1.1.0.sh
```

---

## 📝 Tips

- Press `Ctrl+C` to stop following logs
- Use `--tail N` to show last N lines
- Logs are delayed by ~5-10 seconds
- JSON logs can be parsed with `jq` or `python -m json.tool`
- Worker logs show job processing details
- AppServer logs show Rhino.Compute interaction
- Rhino VM logs show Grasshopper execution errors

---

## 🔗 Full Command Reference

See `./scripts/monitor-logs.sh` for complete list of all commands.

