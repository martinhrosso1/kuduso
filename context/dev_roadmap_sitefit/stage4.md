# Stage 4 — Swap in Real Rhino.Compute (single node)

You’ll replace the mock solver with a real Grasshopper definition executed by Rhino.Compute, *without changing your public API*.

---

# 4.1 Objectives (what “done” looks like)

* AppServer calls **Rhino.Compute** `/grasshopper` for `definition@version`.
* The same **inputs.schema.json → outputs.schema.json** contract holds.
* A “golden” input returns a **known, stable** result (deterministic KPIs/placement).
* Errors are categorized (`400/422/429/504`) and time-boxed per `manifest.json`.

---

# 4.2 Prep the Grasshopper definition (headless-safe)

Make a tiny, deterministic **`sitefit.ghx`** that can run **headless**:

1. **Parameters (names & types)**
   Match your `bindings.json` precisely (case-sensitive).

   * Inputs (examples):

     * `parcel_polygon : Curve` (single closed planar curve)
     * `house_polygon  : Curve`
     * `theta_deg      : Number`
     * `dx_m           : Number`
     * `dy_m           : Number`
   * Outputs:

     * `feasible       : Boolean`
     * `kpi_yard_m2    : Number`
     * `placed_curve   : Curve` (or Mesh/Brep if you prefer)

2. **No UI / No Expensive Solvers**
   Avoid components that need the Rhino UI or interactive prompts. Prefer pure GH components and known headless-safe plugins only.

3. **Determinism**

   * Remove randomness or seed it explicitly (your `seed` input).
   * Avoid relying on file system or global state.

4. **Units**

   * Decide on **meters & degrees** (document in schema).
   * Normalize CRS **before** AppServer calls GH (Python pre-step from earlier stages).

5. **Performance guardrails**

   * Keep the graph simple at first.
   * Avoid exploding sample grids in MVP; try O(10^2) evaluations max.

6. **Save as `ghx`** (XML) to ease version control.

---

# 4.3 Version/compatibility files (kept in `contracts/{def}/{ver}/`)

* `plugins.json` — strict list of required plugins with **exact versions**.
  Example:

  ```json
  [
    {"id":"Human", "version":"1.0.000"},
    {"id":"Pufferfish", "version":"3.3.0"}
  ]
  ```
* `manifest.json` — runtime caps:

  ```json
  {
    "timeout_sec": 120,
    "max_vertices": 5000,
    "max_samples": 200,
    "max_area_m2": 20000
  }
  ```
* `bindings.json` — JSONPath → GH param mapping:

  ```json
  {
    "algo": "/opt/compute/sitefit/1.0.0/sitefit.ghx",
    "params": [
      {"gh": "parcel_polygon", "jsonpath": "$.parcel.coordinates"},
      {"gh": "house_polygon",  "jsonpath": "$.house.coordinates"},
      {"gh": "theta_deg",      "jsonpath": "$.rotation.theta"},
      {"gh": "dx_m",           "jsonpath": "$.translation.x"},
      {"gh": "dy_m",           "jsonpath": "$.translation.y"}
    ],
    "pointer": true
  }
  ```

  > `pointer: true` tells Compute you’re passing **values array** and referencing a **file path** on the Compute machine.

---

# 4.4 Place the GHX on the Compute VM

* Put `sitefit.ghx` under a **versioned folder** on the VM, e.g.:
  `C:\compute\sitefit\1.0.0\sitefit.ghx`
  (If you run Linux, similar path under `/opt/compute/...`.)
* Ensure the **App Pool identity** (IIS) or service user can read it.
* Keep a *“golden image”* or install script with **Rhino + plugins** versions to rebuild easily later (Stage 5 moves to VMSS).

---

# 4.5 Flip the AppServer to real compute

**Config (env):**

```
USE_COMPUTE=true
COMPUTE_URL=http://<rhino-vm-ip>:8081/
COMPUTE_API_KEY=<from Key Vault>
TIMEOUT_MS=120000  # match manifest; add small headroom in app
```

**Plugin attestation (fast)**
On AppServer startup, call a **Compute diagnostic endpoint** you expose (or a small local inventory tool) to list installed plugins and compare to `plugins.json`. If mismatch, mark definition unavailable and return `503`/`422` with a clear error.

---

# 4.6 AppServer call shape (Node → Compute `/grasshopper`)

**Request body** (pointer mode, file path lives on VM):

```json
{
  "algo": "C:\\\\compute\\\\sitefit\\\\1.0.0\\\\sitefit.ghx",
  "pointer": true,
  "values": [
    { "ParamName": "parcel_polygon", "InnerTree": { "0": [ { "type":"Curve", "data": { "curve": "<encoded polyline>" } } ] } },
    { "ParamName": "house_polygon",  "InnerTree": { "0": [ { "type":"Curve", "data": { "curve": "<encoded polyline>" } } ] } },
    { "ParamName": "theta_deg",      "InnerTree": { "0": [ { "type":"System.Double", "data": 0 } ] } },
    { "ParamName": "dx_m",           "InnerTree": { "0": [ { "type":"System.Double", "data": 0 } ] } },
    { "ParamName": "dy_m",           "InnerTree": { "0": [ { "type":"System.Double", "data": 0 } ] } }
  ]
}
```

**Notes**

* Compute expects **Grasshopper Data Trees** (`InnerTree`), with branches `"0"`, `"1"`, etc.
* For geometry, encode with **rhino3dm** helpers (polyline → `Curve`/`PolylineCurve`). Do this translation once in AppServer.
* Always pass **units** & CRS-normalized coordinates (meters) as per your earlier pipeline.

**Headers**

```
Content-Type: application/json
RhinoComputeKey: <COMPUTE_API_KEY>
x-correlation-id: <cid>
```

**Response mapping**

* Parse `values[]` from Compute response → map to your **outputs.schema.json**:

  * `feasible` → boolean
  * `kpi_yard_m2` → number
  * `placed_curve` → convert to GeoJSON or glTF (mesh) as per your packaging rules

---

# 4.7 Error taxonomy & timeouts

* **Input schema errors** → `400` (caught before hitting Compute).
* **Domain errors** (e.g., non-planar curve) → `422`.
* **Compute busy/seat limits** → return `429` (AppServer should maintain a small semaphore per definition and short-circuit if too many concurrent solves).
* **Timeout** (exceeds `manifest.timeout_sec`) → **cancel request**, return `504`. Abort the HTTP call; don’t let runaway GH burn the seat.
* **Upstream failure** (Compute down) → `502/503` with retryable hint for Worker.

Make sure the **Worker** treats `429/502/503/504` as **transient** (abandon → retry), but treats `400/422` as **poison** (dead-letter with reason).

---

# 4.8 Performance & resource caps (first pass)

* Concurrency = **number of Rhino seats** (start with **1**). Use an in-process **semaphore** in AppServer so you don’t flood Compute.
* Memory guard: reject parcels with >N vertices (`manifest.max_vertices`).
* Sampling cap: bound grid/angle sampling by `manifest.max_samples`.
* Response size: keep inline JSON small; push heavy meshes to **Blob** and return **SAS** URLs in `artifacts[]`.

---

# 4.9 Security

* **No public** Rhino in production: keep the VM behind **NSG** (dev) and later an **Internal Load Balancer** (Stage 5).
* **API key** must be present (`RhinoComputeKey` header) and match the VM’s `RHINO_COMPUTE_KEY`.
* AppServer is **internal-only**; only API/Worker can call it.

---

# 4.10 Golden tests (acceptance)

Add these to your CI and run after deployment:

1. **Happy path**

   * Input: square parcel 10×8 m, house 4×3 m.
   * Expect: `feasible=true`, `placed_curve` non-empty, KPIs stable within a tiny tolerance.

2. **Domain invalid**

   * Non-closed parcel → `422`.

3. **Timeout**

   * Force slow branch → AppServer aborts at `manifest.timeout_sec` → `504`.

4. **Seat limit**

   * Launch N+1 parallel jobs with N seats → immediate `429` from AppServer (no long waits).

5. **Plugin mismatch** (simulate)

   * Uninstall a required plugin or bump version → AppServer health for that def becomes **unavailable**; `503` with clear error.

---

# 4.11 Rollout & rollback

* **Feature flag** per definition: `USE_COMPUTE=true|false`.

  * Roll out to **staging** first; compare golden outputs vs. mock.
  * If anything drifts, flip back to `false` → you instantly return to the mock solver (no public outage).
* Keep **revisions** for AppServer; if needed, route traffic back to the previous revision.

---

# 4.12 Diagnostics playbook

* **Compute unreachable** → check NSG, service status, and `COMPUTE_URL`.
* **401 from Compute** → header name or key mismatch; confirm `RhinoComputeKey`.
* **Slow first request** (IIS cold start) → add warm-up pings or Application Initialization.
* **Weird geometry** → log the exact GH inputs your binder created (WKT/GeoJSON for curves) and the branch structure sent to `/grasshopper`.

---

# 4.13 Minimal Node snippets (AppServer)

**Binding → DataTree helper (pseudo-TS)**

```ts
import rhino3dm from "rhino3dm";

function polygonToCurve(poly: number[][]) {
  const pts = new rhino3dm.Polyline();
  poly.forEach(([x,y]) => pts.add(x, y, 0));
  const plc = new rhino3dm.PolylineCurve(pts);
  return { type: "Curve", data: { curve: rhino3dm.CommonObject.encode(plc) } };
}

function asTree(param: string, value: any) {
  return { ParamName: param, InnerTree: { "0": [ value ] } };
}
```

**Call Compute**

```ts
const body = {
  algo: "C:\\\\compute\\\\sitefit\\\\1.0.0\\\\sitefit.ghx",
  pointer: true,
  values: [
    asTree("parcel_polygon", polygonToCurve(parcel)),
    asTree("house_polygon",  polygonToCurve(house)),
    asTree("theta_deg",      { type:"System.Double", data: theta }),
    asTree("dx_m",           { type:"System.Double", data: dx }),
    asTree("dy_m",           { type:"System.Double", data: dy })
  ]
};

const resp = await fetch(`${COMPUTE_URL}grasshopper`, {
  method: "POST",
  headers: { "Content-Type":"application/json", "RhinoComputeKey": COMPUTE_API_KEY, "x-correlation-id": cid },
  body: JSON.stringify(body),
  signal: AbortSignal.timeout(TIMEOUT_MS)
});
```

**Map response → outputs**

```ts
// parse resp.json().values → pick by OutputName
// then package { results[], artifacts[], metadata{} } per outputs.schema.json
```

---

## TL;DR

* Prepare a **headless-safe GHX** with strict param names and deterministic outputs.
* Put the file on the Compute VM; verify plugins match `plugins.json`.
* Flip `USE_COMPUTE=true` in AppServer; implement `/grasshopper` call and bindings.
* Enforce **caps & timeouts** from `manifest.json`; map errors to clean HTTP codes.
* Pass your **golden tests**—then you’re officially running the real engine with zero public API change.
