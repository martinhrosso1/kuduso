# Step 9: Install Rhino 8 (Manual Step)

**This step requires manual installation and cannot be fully automated.**

---

## Prerequisites

✅ Complete steps 1-8 first
✅ Have a McNeel account with Cloud Zoo license

---

## Option A: Interactive Installation (Recommended)

### 1. Download Rhino 8

Visit: https://www.rhino3d.com/download/

Or direct link: https://www.rhino3d.com/download/rhino-for-windows/8/latest/direct

### 2. Run Installer

1. Double-click the downloaded installer
2. Accept license agreement
3. Choose installation type: **Complete**
4. Installation location: `C:\Program Files\Rhino 8\` (default)
5. Wait for installation (~10 minutes)

### 3. Activate License

1. Launch Rhino 8 from Start Menu
2. When prompted for licensing, choose **Cloud Zoo**
3. Click **Sign In**
4. Enter your McNeel account credentials
5. Select your license from the list
6. Close Rhino

### 4. Verify Installation

Open PowerShell and run:

```powershell
# Check if Rhino is installed
Test-Path "C:\Program Files\Rhino 8\System\Rhino.exe"

# Should return: True
```

---

## Option B: Silent Installation (Advanced)

```powershell
# Download installer
$installerUrl = "https://www.rhino3d.com/download/rhino-for-windows/8/latest/direct"
$installerPath = "$env:TEMP\rhino_8_setup.exe"

Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

# Silent install with Cloud Zoo
Start-Process $installerPath -ArgumentList @(
  '/quiet',
  '/norestart',
  'LICENSE_METHOD=CLOUD_ZOO'
) -Wait

# Verify
Test-Path "C:\Program Files\Rhino 8\System\Rhino.exe"
```

**Note:** Silent install still requires **interactive Cloud Zoo sign-in** on first Rhino launch.

---

## Option C: LAN Zoo (Fully Automated)

If you have a LAN Zoo server:

```powershell
# Install with LAN Zoo
Start-Process $installerPath -ArgumentList @(
  '/quiet',
  '/norestart',
  'LICENSE_METHOD=ZOO',
  'ZOO_SERVER=zoo.yourcompany.com:80'
) -Wait
```

---

## Verify License Activation

```powershell
# Launch Rhino
& "C:\Program Files\Rhino 8\System\Rhino.exe"

# In Rhino:
# 1. Go to: Tools → Options → Licenses
# 2. Verify license shows as "Cloud Zoo" or "LAN Zoo"
# 3. Status should be "Valid"
```

---

## Troubleshooting

### License Not Found

- Ensure you're signed into the correct McNeel account
- Verify license is available in Cloud Zoo team
- Check internet connectivity

### Installation Fails

- Run installer as Administrator
- Disable antivirus temporarily
- Check Windows Update is not running
- Ensure .NET Desktop Runtime is installed (Step 3)

---

## Next Steps

After Rhino 8 is installed and licensed:

✅ **Continue to Step 10:** Run `10-test-compute.ps1` to verify everything works

---

## Additional Resources

- Rhino Installation Guide: https://wiki.mcneel.com/rhino/installingrhino
- Cloud Zoo Setup: https://www.rhino3d.com/6/new/licensing-and-administration
- McNeel Support: https://www.rhino3d.com/support
