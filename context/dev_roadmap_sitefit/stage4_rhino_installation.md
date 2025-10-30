
Guide to get **Rhino.Compute** running on your Azure Windows VM and wired to your AppServer.

---

# 1) VM prerequisites (once)

1. **Image & size**

   * Windows Server 2022 (Datacenter) on a D2as_v5 or D4as_v5 is a good start.
   * Make sure you can RDP into it and you’ve locked inbound NSG to **your IP only** for now.

2. **Install Rhino 8 (Windows)**

   * Sign in with the Rhino account that owns the license (Cloud Zoo). Rhino 8 is required for current Compute builds. ([GitHub][1])

3. **Install the Compute server**

   * Follow McNeel’s Compute “Getting Started / Deploy to IIS” guides; you can run it **as an IIS site** (recommended for production) or **self-hosted Kestrel** for quick tests. ([www.rhino3d.com][2])

4. **.NET + IIS features**

   * Ensure the **.NET Desktop Runtime** and **IIS** role (with ASP.NET Core hosting bundle) are installed if you plan to host under IIS. The McNeel “Deploy to IIS” guide walks this. ([www.rhino3d.com][3])

---

# 2) Two supported run modes

## A) Quick start (self-hosted / Kestrel)

Good for verifying the box before you touch IIS.

* Launch the **compute.rhino3d** server (from the official repo/build) and let it listen on `http://localhost:8081/`.
* Set the **API key** as a Windows **system environment variable**:

  * Name: `RHINO_COMPUTE_KEY`
  * Value: a long random string (you’ll send it as a header later).
  * Restart the Compute service/exe after setting it. ([McNeel Forum][4])
* Open the VM’s firewall/NSG to **port 8081** from **your IP only** (test phase).

## B) Production-ish (IIS reverse-proxy)

Recommended for steady uptime & autos-restart.

* Install **IIS** and the **ASP.NET Core Hosting Bundle**.
* Create a new **IIS site** (e.g., bind to port **80** internally).
* Configure the site to start the **Compute** backend and forward requests to the geometry worker. McNeel’s “Deploy to IIS” guide covers the steps and app pool details. ([www.rhino3d.com][3])
* Set `RHINO_COMPUTE_KEY` in **System Properties → Environment Variables** (not just user-level). ([McNeel Forum][4])
* Optional but recommended: configure **HTTPS** on the IIS site (Compute supports HTTPS; McNeel has a dedicated guide). ([www.rhino3d.com][5])

> Tip: IIS will “cold start” after long idle periods; you can add an IIS **Application Initialization** warm-up, or have your AppServer ping `/version` every few minutes. Azure users have reported 20–30s warmups without it. ([McNeel Forum][6])

---

# 3) Network & security checklist

* **During testing**: allow inbound 80/8081 **from your current IP only**.
* **For production**: make **no public IP** and front Compute with an **Internal Load Balancer**; only your **AppServer** subnet/IPs can reach it (what we planned for your architecture).
* **Auth header**: clients must send `RhinoComputeKey: <your key>` on **POST** requests (401 otherwise). Key value must match `RHINO_COMPUTE_KEY` on the VM. ([McNeel Forum][7])

---

# 4) Configure Rhino/Grasshopper plugins

* Ensure any GH plugins used by your definitions are installed on the VM and match versions you list in your **`plugins.json`** (your AppServer does plugin attestation).
* Keep a **golden image** or automation script for repeatable plugin installs when you later move to VM Scale Sets.

---

# 5) Sanity tests (from your laptop)

Replace `VM_IP` with the VM’s public IP (test phase) or private ILB IP (prod).

1. Server up?

   ```bash
   curl http://VM_IP:8081/version
   ```

   You should get a small JSON/version response (no key needed for GET endpoints like `/version` or `/activechildren`). ([McNeel Forum][4])

2. Auth check (POST requires key):

   ```bash
   curl -i -X POST http://VM_IP:8081/rhino/geometry/points \
     -H "Content-Type: application/json" \
     -H "RhinoComputeKey: <YOUR_KEY>" \
     -d '{"points":[[0,0,0],[1,0,0]]}'
   ```

   (Any valid Compute POST endpoint works; the key name **must** be `RhinoComputeKey`.) ([McNeel Forum][7])

3. Grasshopper endpoint smoke (tiny test)
   Send a minimal `/grasshopper` payload with a trivial GH file to confirm end-to-end GH execution (follow McNeel’s “Running & Debugging Compute Locally” guide for example payloads; point `algo` to your GHX). ([www.rhino3d.com][8])

---

# 6) Wire to your AppServer (what to set)

In your **AppServer (Node)** container env:

* `COMPUTE_URL` → `http://VM_IP:8081/` (test) or the **ILB** URL later.
* `COMPUTE_API_KEY` → same value as `RHINO_COMPUTE_KEY`.
* Timeouts: start with 240s; enforce caps from your `manifest.json`.

Your AppServer will send:

```
POST /grasshopper
Headers:
  RhinoComputeKey: <COMPUTE_API_KEY>
Body:
  { "algo":".../sitefit.ghx", "pointer":true, "values":[...] }
```

---

# 7) Common snags (and fixes)

* **401 Unauthorized**: missing/incorrect header name—use `RhinoComputeKey` exactly; value must equal VM’s `RHINO_COMPUTE_KEY`. ([McNeel Forum][7])
* **Cold starts feel slow**: add IIS warm-up pings or keep-alive from AppServer. ([McNeel Forum][6])
* **Version mismatch (Rhino 7 vs 8)**: run the **Compute branch** that matches your installed Rhino (7.x vs 8.x). ([www.rhino3d.com][8])
* **Not reachable from outside**: check NSG/Windows Firewall + that the site binds to the right port, and you’re using the exposed port (80/8081). A past Azure thread flags this exact gotcha. ([McNeel Forum][9])

---

# 8) When you’re happy (hardening next)

* Move the VM into your **VNet** and put Compute **behind an Internal Load Balancer**.
* Restrict inbound to the **AppServer subnet** only.
* Consider a **VMSS** with your golden Rhino+plugins image for scale and rolling updates (this is your Stage-5/6 target).

---

## Handy docs

* **Compute Guides (McNeel)**: overview, dev, deploy, HTTPS. ([www.rhino3d.com][2])
* **Azure VM how-to (McNeel)**: creating the VM (basic). ([www.rhino3d.com][10])
* **API key & header name**: env var `RHINO_COMPUTE_KEY`; header `RhinoComputeKey`. ([McNeel Forum][4])

If you want, I can give you an **IIS app settings checklist** (bindings, app pool, warm-up) tailored to your VM once you share the exact Windows build and whether you prefer port 80 or 8081.

[1]: https://github.com/mcneel/compute.rhino3d?utm_source=chatgpt.com "mcneel/compute.rhino3d: REST geometry server based ..."
[2]: https://developer.rhino3d.com/guides/compute/?utm_source=chatgpt.com "Rhino - Compute Guides"
[3]: https://developer.rhino3d.com/guides/compute/deploy-to-iis/?utm_source=chatgpt.com "Rhino - Deployment to Production Servers"
[4]: https://discourse.mcneel.com/t/change-api-key-after-deploying-compute/136966?utm_source=chatgpt.com "Change API Key after deploying compute - McNeel Forum"
[5]: https://developer.rhino3d.com/guides/compute/configure-compute-for-https/?utm_source=chatgpt.com "Configure Compute to use HTTPS"
[6]: https://discourse.mcneel.com/t/best-way-to-fire-up-rhino-compute-on-azure/187892?utm_source=chatgpt.com "Best way to fire up rhino compute on Azure - McNeel Forum"
[7]: https://discourse.mcneel.com/t/calling-compute-endpoints-giving-error/164698?utm_source=chatgpt.com "Calling compute endpoints giving error - McNeel Forum"
[8]: https://developer.rhino3d.com/guides/compute/development/?utm_source=chatgpt.com "Running and Debugging Compute Locally"
[9]: https://discourse.mcneel.com/t/rhino-compute-not-starting-on-azure-vm/142479?utm_source=chatgpt.com "Rhino Compute not starting on Azure VM - McNeel Forum"
[10]: https://developer.rhino3d.com/guides/compute/creating-an-Azure-VM?utm_source=chatgpt.com "How to create a virtual machine (VM) on Azure"
