# Stage 9 — Multi-App Readiness (platform)

Stage 9 is where your single-app platform becomes a **product line**. Below is a concrete plan to make adding a new app (e.g., `yieldcheck`, `daylight`, `parking`) a **parameter change + one deploy**—while keeping shared components stable.

---

# 9.1 Platform principle

**One shared core per environment** (ACA env, ACR, Key Vault, Storage, Service Bus *namespace*, Log Analytics, AppServer, Rhino.Compute), and **N per-app stacks** (API, Worker, SB queue, DB schema, frontend). Apps are isolated but run on the same hardened platform.

---

# 9.2 Tenancy model for “apps”

Introduce **`app_id`** as a first-class key across everything:

* **Messages**: `app_id` property and inside the message body.
* **DB**: every row carries `app_id` (or lives in an app-specific schema).
* **Logs/metrics**: `app_id` label in every log line and metric.
* **Tags**: Azure resources tagged `app_id=<id>`, `env=<env>`.
* **Artifacts**: Blob path prefix `artifacts/<app_id>/<job_id>/…`.
* **Contracts**: versioned at `contracts/<app_id>/<version>/…`.
* **Routing**: public API paths namespaced: `/{app_id}/jobs/run`, `/{app_id}/jobs/status/{id}`, …

---

# 9.3 Per-app isolation options

Pick one; you can mix by criticality.

**A) Shared DB, per-app schema** (good default)

* Single Supabase project.
* Schemas: `sitefit.job`, `daylight.job`, … (or one `public.job` with `app_id` column + RLS on `app_id`).
* Pros: fewer instances, simple to operate.
* Cons: blast radius larger if schema migration breaks.

**B) Per-app DB** (max isolation)

* Separate Supabase projects (or Azure Postgres Flexible) per app.
* Pros: blast radius minimal, scale/resources per app.
* Cons: more overhead and cost.

**C) Hybrid**

* Start shared; promote heavy/regulated apps to dedicated DB later.

> For your current scale, **A** is perfect; design schema so **B** is a drop-in later.

---

# 9.4 Service Bus topology

Two good shapes:

**Queues per app (simple)**

* `jobs-sitefit`, `jobs-daylight`, …
* Worker KEDA scales off its own queue.
* Pros: dead simple, good isolation.
* Cons: cross-app fan-out requires extra logic (rare).

**Topic with per-app subscriptions**

* One topic `jobs`, subs: `sitefit`, `daylight` (SQL filter on `app_id`).
* Pros: centralized publisher, per-app subs/filters.
* Cons: slightly more complex IaC/ops.

> Stick with **queues per app**—matches your current module and keeps failure isolation crisp.

---

# 9.5 AppServer: multi-app policy & registry

The shared **AppServer** becomes an **authoritative registry** of definitions:

* **Directory**: `contracts/<app_id>/<version>/…`

* **Policy file** (per app): `policy.json`

  ```json
  {
    "app_id": "sitefit",
    "allowed_definitions": ["sitefit"],
    "max_concurrency": 2,
    "preview_seats": 1,
    "batch_seats": 1,
    "rate_limits": { "preview_rps": 10, "batch_jobs_per_min": 30 },
    "manifest_overrides": { "timeout_sec": 120 }
  }
  ```

* **At startup**, AppServer:

  * Loads all `policy.json` & contracts.
  * Attests plugins per definition@version against the Rhino nodes.
  * Exposes `/health/registry` showing available defs per app.

* **At runtime**:

  * Enforces **per-app** caps (concurrency, timeouts, size limits).
  * Namespaces caches by `app_id` (preview LRU, result memo).
  * Logs include `app_id` consistently.

---

# 9.6 API & Worker: multi-app aware

* **Routing**: `/{app_id}/jobs/run`, `/{app_id}/jobs/status/{id}`, `/{app_id}/jobs/result/{id}`

* **Validation**:

  * Ensure `app_id` exists and the **caller is allowed** (tenant → app mapping).
  * Validate inputs against `contracts/<app_id>/<version>/inputs.schema.json`.

* **Queue binding**:

  * API resolves queue from `app_id` → `jobs-${app_id}`.
  * Worker instance is deployed **per app** and consumes its own queue.

* **Config**:

  * `APP_ID` env var baked into each API/Worker deployment.
  * `APP_SERVER_URL` stays common, but body includes `{ app_id, definition, version }`.

---

# 9.7 IaC: “stamp a new app” module

Create/extend **`infra/modules/app-stack`** to accept `app_id` and produce a ready app:

* **Inputs**: `app_id`, images, queue name, env URLs, KV secret names
* **Creates**:

  * SB queue `jobs-${app_id}`
  * ACA `api-${app_id}` (external)
  * ACA `worker-${app_id}` (internal) + KEDA scale rule
  * Optionally per-app dashboard & alert resources
* **Outputs**: API FQDN, queue name.

Then add a Terragrunt shim:

```
infra/live/dev/apps/<app_id>/terragrunt.hcl
```

with just the parameters. To create App #2 you copy this folder, change `app_id`, and apply.

---

# 9.8 CI/CD templates per app

* **Build**: on changes under `apps/<app_id>/**`, build & push:

  * `<acr>/api-fastapi:${SHA}`, `<acr>/worker-fastapi:${SHA}`
* **Deploy**: `terragrunt run-all apply --terragrunt-include-dir infra/live/<env>/apps/<app_id>`
* **Contracts**: if `contracts/<app_id>/<version>` changed, run:

  * **schema lint**, **example validation**, **breaking change check** (see §9.12)
  * publish version artifact (npm PyPI SDK bump optional).

---

# 9.9 Logging, metrics, and cost per app

* **Logging**: Include `app_id` in every log; KQL dashboards group by `app_id`.
* **Metrics**: Queue len, p95 job latency, 4xx/5xx by `app_id`.
* **Cost tags**: `app_id` on all per-app resources (API/Worker/queue); Blob prefix per app.
* **Dashboards**: one global, plus per-app workbook filtered on `app_id`.

---

# 9.10 Security boundaries

* **Auth**: API verifies token, maps `tenant_id` to **allowed app_ids**.
* **Rate limits**: per tenant per app; separate preview vs batch.
* **RLS** (if shared DB): `tenant_id` → rows; **and** `app_id = ANY(allowed_apps(tenant))`.
* **AppServer** rejects calls for undefined `app_id` or unauthorized tenants.

---

# 9.11 Versioning & compatibility matrix

* Allow **multiple versions** side-by-side: `sitefit@1.0.0`, `sitefit@1.1.0`.
* AppServer health shows which versions are **ready** (plugins present).
* API allows clients to request `{version}`; default to `stable` alias.
* Keep a **compat matrix**:

  ```
  app_id   version   requires_plugins_hash   status(ready|degraded)
  sitefit  1.0.0     9f2a...                 ready
  sitefit  1.1.0     a13c...                 ready
  daylight 0.1.0     77ab...                 degraded (missing LadybugX.Y)
  ```
* Roll out by adding a **new version folder** on Rhino VM, then flipping clients.

---

# 9.12 Contract governance (multi-app safety)

Automate checks in CI:

* **Schema semantic checks**: forbid removing required fields between minor versions.
* **Example validation**: `examples/valid/*` must validate; `invalid/*` must fail.
* **Bindings sanity**: all `gh` param names present in GHX for that version.
* **Plugins attestation hash**: `plugins.json` → normalized → SHA; AppServer refuses mismatches.

---

# 9.13 Onboarding a new app (checklist)

1. **Contracts**

   * Create `contracts/<new_app>/<version>/{inputs,outputs,bindings,manifest,plugins}.json`
   * Add `examples/valid/minimal.json`
2. **Frontend**

   * Create `apps/<new_app>/frontend` (can clone sitefit UI and adjust fields)
3. **API/Worker**

   * Duplicate `apps/sitefit/api-fastapi` → `apps/<new_app>/api-fastapi`
   * Duplicate `apps/sitefit/worker-fastapi` → `apps/<new_app>/worker-fastapi`
   * Set `APP_ID=<new_app>` defaults
4. **AppServer**

   * Add `policy.json` for the new app (concurrency, limits)
   * Place GHX + plugins on Rhino (or blob→sync to local path)
5. **IaC**

   * Copy `infra/live/<env>/apps/sitefit` → `infra/live/<env>/apps/<new_app>`
   * Change `app_id`, queue name, images
6. **CI**

   * Add pipelines (build, deploy)
7. **Apply**

   * `terragrunt run-all apply --terragrunt-include-dir infra/live/dev/apps/<new_app>`
8. **Smoke**

   * POST `/<new_app>/jobs/run` with minimal example; ensure success path
9. **Dashboards/alerts**

   * Duplicate per-app workbook/alerts; filter `app_id=<new_app>`

Time to first hello-world app after the platform exists: **~1–2 hours**.

---

# 9.14 Failure isolation & SLOs per app

* **Queues**: one backlog does not affect others.
* **Workers**: per-app scaling (KEDA); cap replicas individually.
* **AppServer**: per-app semaphores for preview/batch seats.
* **Rhino**: optional node pools (VMSS per app) if one app is heavy.
* **SLOs**: p95 and error budgets tracked per app_id.

---

# 9.15 Example: multi-app routing (FastAPI)

```python
from fastapi import APIRouter, Depends

router = APIRouter(prefix="/{app_id}", tags=["jobs"])

@router.post("/jobs/run")
async def run_job(app_id: str, req: RunRequest, user=Depends(auth)):
    assert app_allowed(user, app_id)
    inputs = materialize_defaults(app_id, req.version, req.inputs)
    job_id = enqueue(app_id, req.definition, req.version, inputs, user.tenant_id)
    return {"job_id": job_id}

@router.get("/jobs/status/{job_id}")
async def job_status(app_id: str, job_id: UUID, user=Depends(auth)):
    assert app_allowed(user, app_id)
    return get_status(app_id, job_id, user.tenant_id)
```

---

# 9.16 Example: app Terragrunt (dev)

```hcl
# infra/live/dev/apps/daylight/terragrunt.hcl
include "root" { path = find_in_parent_folders() }
terraform { source = "../../../modules/app-stack" }

dependency "core"      { config_path = "../../shared/core" }
dependency "appserver" { config_path = "../../shared/appserver" }

inputs = {
  app_id            = "daylight"
  core_rg_name      = dependency.core.outputs.resource_group_name
  acr_server        = dependency.core.outputs.acr_server
  acaenv_id         = dependency.core.outputs.acaenv_id
  kv_name           = dependency.core.outputs.kv_name
  sb_namespace_name = dependency.core.outputs.sb_namespace_name
  storage_account   = dependency.core.outputs.storage_account_name

  api_image         = "${dependency.core.outputs.acr_server}/api-fastapi:${get_env("IMG_SHA","dev")}"
  worker_image      = "${dependency.core.outputs.acr_server}/worker-fastapi:${get_env("IMG_SHA","dev")}"

  database_url_kv_secret_name      = "DATABASE-URL"
  servicebus_conn_kv_secret_name   = "SERVICEBUS-CONN"
  blob_sas_signing_kv_secret_name  = "BLOB-SAS-SIGNING"

  queue_name        = "jobs-daylight"
  appserver_url     = "http://aca-appserver.internal/gh/{def}:{ver}/solve"
  jwt_jwks_url      = "https://<supabase>.supabase.co/auth/v1/keys"
  result_cache_ttl  = 300

  lock_renew_sec    = 45
  job_timeout_sec   = 240
  max_worker_replicas = 3
}
```

---

# 9.17 Exit criteria (measurable)

* **Create App #2** by copying the app stack folder, changing `app_id`, pushing images, and `terragrunt apply` → works first try.
* Dashboards & alerts show **per-app** breakdown automatically.
* **RLS** (if shared DB) ensures tenants can only see their app’s rows.
* **No platform change** needed to add a new app.

---

## TL;DR

Bake **`app_id`** into every layer, keep **one hardened platform**, and stamp **per-app stacks** (API, Worker, queue, optional schema/UI). AppServer becomes a **policy-enforced registry** for definitions with per-app concurrency and rate limits. With a small Terragrunt shim, adding a new app is literally **change `app_id` + deploy**—and you get isolation, observability, and cost tracking per app for free.
