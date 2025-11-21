# Deploy v1.1.0 to Rhino VM

## Quick Deploy via RDP

1. **Connect to VM with folder sharing:**
   ```bash
   VM_IP=$(az vm show --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm --show-details --query "publicIps" -o tsv)
   xfreerdp /v:$VM_IP /u:rhinoadmin \
     /dynamic-resolution /cert:ignore \
     /drive:local,/home/martin/Desktop/kuduso/contracts/sitefit/1.1.0 &
   ```

2. **In VM PowerShell, run:**
   ```powershell
   # Create directory
   New-Item -ItemType Directory -Path 'C:\compute\sitefit\1.1.0' -Force
   
   # Copy GHX file
   Copy-Item '\\tsclient\local\ghlogic.ghx' -Destination 'C:\compute\sitefit\1.1.0\ghlogic.ghx'
   
   # Verify
   Get-Item 'C:\compute\sitefit\1.1.0\ghlogic.ghx' | Format-List Length, LastWriteTime
   
   # Restart IIS
   iisreset
   ```

3. **Test from local machine:**
   ```bash
   curl -X POST "https://kuduso-dev-sitefit-api.blackwave-77d88b66.westeurope.azurecontainerapps.io/jobs/run" \
     -H "Content-Type: application/json" \
     -d '{
       "app_id": "sitefit",
       "definition": "sitefit",
       "version": "1.1.0",
       "inputs": {"value": 42}
     }'
   ```

4. **Check result (should be 52):**
   ```bash
   curl "https://kuduso-dev-sitefit-api.../jobs/result/{job_id}"
   ```

## Expected Output

```json
{
  "result": 52
}
```

## If It Works

✅ Infrastructure is good (API → Worker → AppServer → Rhino.Compute)  
✅ GHX file loading works  
✅ Parameter passing works  
✅ Output mapping works  

**Next:** Debug why 1.0.0 fails (probably GHX file structure or Python script)

## If It Fails

Check AppServer logs for specific error:
```bash
az containerapp logs show \
  --name kuduso-dev-appserver \
  --resource-group kuduso-dev-rg \
  --tail 50
```

Common issues:
- 500: GHX file malformed (try opening in Grasshopper on VM)
- 504: Rhino.Compute not responding
- 422: Output doesn't match schema

