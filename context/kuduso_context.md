# Project Context — *Kuduso* (for Windsurf)

> **Goal**: Give Windsurf (and new devs) the exact context to build and run the Kuduso MVP using **ACA + Service Bus + AppServer + Rhino.Compute + Supabase + Azure Blob Storage**. This is the single source of truth for architecture, folders, contracts, and run steps.

---

## 1) Project overview

Kuduso is a platform for building web apps that turn user inputs into 2D/3D geometry, descriptive documents, or decision-ready insights. It standardizes the whole flow from validated frontend parameters to reproducible backend computes, offering both instant previews and authoritative batch runs. Under the hood, Kuduso is powered by Rhino.Compute and Grasshopper, wrapped in contract-driven services so apps stay consistent, scalable, and easy to extend.

Kuduso repository is structured as a monorepo with the following main components:

- `contracts/` - contracts (folder per each web app, versioned)
- `apps/` - web apps (folder per each web app)
- `shared/` - shared code
- `infra/` - infrastructure as code for the shared platform
- `packages/` - shared packages
- `tests-e2e/` - end-to-end tests

Flow: **Next.js (Vercel)** → **API (FastAPI/ACA)** → **Azure Service Bus** → **Worker (ACA)** → **AppServer (Node/ACA)** → **Rhino.Compute (Windows VMSS)** → results in **Supabase DB + Azure Blob Storage**.


### Sitefit app  (MVP)
As a part of this context, we include also MVP of Sitefit app. It will be the first app in the Kuduso platform.

Sitefit is a web app that places a house footprint onto a land parcel under constraints.
---

## 2) Repo layout (monorepo)

```
kuduso/
  contracts/
    sitefit/1.0.0/
      inputs.schema.json
      outputs.schema.json
      bindings.json
      manifest.json
      plugins.json
      README.md
      examples/
        valid/minimal.json
        valid/typical.json
        invalid/missing-required.json
  apps/
    sitefit/
      frontend/           # Next.js (Vercel)
      api-fastapi/        # external API (enqueue/status/result) + SB producer
      worker-fastapi/     # internal worker (SB consumer) + lock renewal
  shared/
	  appserver-node/     # internal-only (schemas, GH routing, glTF/GeoJSON packaging)
  infra/
    modules/                 # reusable building blocks (pure HCL)
      shared-core/           # RG, ACR, Log Analytics, Key Vault, Service Bus NS, Storage, ACA env
      shared-appserver/      # ACA app: appserver-node (internal-only)
      app-stack/             # per-app: API + Worker + SB queue + KEDA scaling
      rhino-vm/              # phase-1 Rhino VM (public IP + NSG)
      rhino-vmss-ilb/        # phase-2 Rhino VMSS behind Internal Load Balancer
      network/               # (optional) VNet, subnets, NAT, Private Endpoints
      dns/                   # (optional) zone/records for API hostnames
    live/                    # env-specific orchestration with Terragrunt
      dev/
        shared/              # the *platform* for dev
          core/              # shared-core module
          appserver/         # shared-appserver module
          rhino/             # rhino-vm (or rhino-vmss-ilb later)
          network/           # (optional at first)
        apps/                # per-app stacks (repeat per app)
          sitefit/           # app-stack module for sitefit
            terragrunt.hcl
          anotherapp/
            terragrunt.hcl
        terragrunt.hcl       # env root (remote state, providers, common tags)
      prod/
        ... same structure ...
  packages/
    ts-sdk/             # optional shared TypeScript client (generated from OpenAPI + JSON Schemas)
    py-sdk/             # optional Python client/types shared by api/worker
    util-geometry/      # small cross-lang utils if needed (or keep per-language)
  tests-e2e/
    api/                # pytest/httpx or Playwright hitting local/dev stack
    ui/                 # Playwright journeys (run → poll → show result)
  .github/workflows/    # or ADO pipelines
  context/              # AI development context files
  Makefile   # or Taskfile.yml
```

---

## 3) Architecture outline

- **Frontend — Next.js (Vercel)**
    - Public UI, calls your API over HTTPS.
    - CORS locked to Vercel domains.
- **API — FastAPI on Azure Container Apps (ACA, *external*)**
    - Verifies Supabase JWT (auth/tenancy).
    - **Enqueues a message to Azure Service Bus** (Queue or Topic) with the job payload (`tenant_id`, `app_id`, normalized inputs, `inputs_hash`).
    - Persists **job metadata** (id, status=queued, `inputs_hash`) to Supabase for status/result lookups.
    - Returns `202 { job_id }`; serves `/status` and `/result` from Supabase.
- **Worker — FastAPI on ACA (*internal-only*)**
    - **Consumes from Service Bus** with *peek-lock*; uses **lock renewal** during long GH runs.
    - Calls AppServer → Rhino, writes results/artifact metadata to Supabase, **completes** the message.
    - On failures: **abandon** (retries) → **DLQ** after N attempts; exponential backoff via SB retry policy.
    - **Scales on queue length** using ACA/KEDA’s Service Bus scaler; run **1 job per replica** (align with Rhino license seats).
- **AppServer — Node.js on ACA (*internal-only*)**
    - Enforces **JSON Schemas**, limits/timeouts, plugin attestation.
    - Maps JSON ⇄ Grasshopper Data Trees; returns KPIs + glTF/GeoJSON.
    - No public ingress.
- **Rhino.Compute — Windows VM Scale Set (VMSS) + Internal Load Balancer**
    - Headless Rhino/Grasshopper workers; **no public IP**.
    - Concurrency capped to license seats; identical Rhino/plugin image.
- **Messaging — Azure Service Bus**
    - **Queue** (simple) or **Topic + Subscriptions** (if you plan multiple consumer types later).
    - **Sessions** optional: use per-`tenant_id` sessions to preserve per-tenant ordering and enforce per-tenant concurrency.
    - **DLQ** enabled; operator can peek/repair/replay dead-lettered jobs.
    - Tier: **Standard** for MVP (public endpoint). If you require **Private Link**, use **Premium**.
- **DB + Auth — Supabase (Postgres + PostGIS + RLS + JWT)**
    - Public endpoint **IP-allowlisted** to your ACA **egress IP** only (via NAT).
    - Stores parcels/houses, **job metadata/status/results** (artifacts live in Blob).
- **Storage — Azure Storage Account (Blob)**
    - Artifacts (glTF/GeoJSON) via **SAS** URLs.
    - Lifecycle policy to prune old runs.
- **Secrets — Azure Key Vault (minimal add)**
    - Stores Supabase creds, Service Bus connection/credentials (or Managed Identity), Rhino API key, SAS signing key.
    - Accessed via **managed identity** from ACA.
- **Observability — Azure Monitor / Log Analytics (minimal add)**
    - Collects API/Worker/AppServer logs & metrics.
    - Dashboards: **SB queue depth / DLQ depth**, p95 solve time, success rate, per-tenant throughput.
- **Networking (tiny but crucial constraints)**
    - **One ACA Environment + VNet**:
        - API (external), Worker (internal), AppServer (internal) in same env/VNet.
    - **(Optional) NAT Gateway** on the ACA subnet → **static egress IP** (for Supabase allowlist).
    - **Private east–west**: Worker/AppServer → Rhino via **internal load balancer**.
    - Service Bus: **Standard** uses public endpoint (OK for MVP). If you need private networking, plan **Premium** later.
---

## 4) Contracts (source of truth)

Located in `contracts/{app_name}/{version}/`:

Great call. Here’s a **generalized Contracts section** you can drop into the context file—works for *any* Kuduso app, not just SiteFit.

---

## 4) Contracts (source of truth)

Contracts live under `contracts/{definition_name}/{version}/` and describe **what the app expects** and **what it returns**, independent of any specific UI or backend. Every runtime component (API, Worker, AppServer, tests) **imports** these files—no copy/paste types.

**Folder layout (per definition & version)**

```
contracts/
  {definition_name}/
    {semver}/
      inputs.schema.json
      outputs.schema.json
      bindings.json
      manifest.json
      plugins.json
      README.md            # optional: human docs/examples
      examples/            # optional: valid/invalid sample payloads
```

**Files (what they mean, generically)**

* **`inputs.schema.json`**
  JSON Schema for the **request**. Defines required parameters, types, units/CRS where relevant, allowed ranges, and enums.
  *Examples:* geometry arrays, numeric sliders (angles/offsets), categorical options, toggles, random `seed`.

* **`outputs.schema.json`**
  JSON Schema for the **response**. Captures canonical results (e.g., transforms, KPIs, scores) and optional **artifacts** metadata (links to glTF/GeoJSON/documents).
  *Examples:* `{ placements[], kpis{}, score, artifacts[] }`.

* **`bindings.json`**
  Declarative mapping from **input JSON** to **compute graph parameters** (e.g., Grasshopper or other engines). Uses JSONPath or field names to avoid custom glue code.
  *Examples:* `$.geometry.building → gh:building_polygon`, `$.options.rotation → gh:theta`.

* **`manifest.json`**
  Operational limits and execution hints the AppServer enforces **before** calling the compute engine.
  *Examples:* `timeout_sec`, `max_vertices`, `max_samples`, `concurrency_class` (`preview` vs `batch`), required coordinate system, numeric bounds.

* **`plugins.json`**
  Exact runtime inventory required by the compute graph (engine version + plugin names/versions). AppServer **rejects** mismatches to keep runs reproducible.
  *Examples:* `{"rhino":"8.7.x","plugins":[{"name":"Human","version":"1.3.2"}]}`

**Conventions**

* **Versioning:** semantic (`MAJOR.MINOR.PATCH`). Breaking changes = new **MAJOR** folder.
* **Determinism:** if randomness is used, include a `seed` in inputs and record it in outputs.
* **Units/CRS:** always explicit (e.g., `units: "m"`, `crs: "EPSG:xxxx"`).
* **Validation:** APIs/AppServer validate **strictly** against these schemas. No “best effort” coercion.

> **Rule:** Services **import** these files at runtime or build-time (codegen/types). They never re-declare shapes manually.

---

## 5) APIs & messaging

### Public API (FastAPI, external)

* `POST /jobs/run`

  * **Purpose:** enqueue an authoritative compute run for a specific **definition@version**.
  * **Auth:** user JWT.
  * **Body (envelope):**

    ```json
    {
      "app_id": "string",
      "definition": "{definition_name}",
      "version": "x.y.z",
      "inputs": { /* contracts/{definition}/{version}/inputs.schema.json */ }
    }
    ```
  * **Behavior:** validate envelope + inputs → compute `inputs_hash` → write **job metadata** (e.g., `status='queued'`, `tenant_id`, `app_id`, `inputs_hash`) → **enqueue message** to the platform queue → `202 { "job_id": "uuid" }`.

* `GET /jobs/status/{job_id}`

  * Returns `{ "status": "queued|running|succeeded|failed", "attempts": n, "last_error": {...}? }`.

* `GET /jobs/result/{job_id}`

  * Returns data shaped by **outputs.schema.json** (example):

    ```json
    {
    // placements are specific to Sitefit app
      "placements": [ { "theta": 0, "dx": 0, "dy": 0, "score": 0, "kpis": { } } ],
    // artifacts and metadata are generic for all apps
      "artifacts": [ { "kind": "geojson|gltf|pdf", "url": "signed-url", "expires_at": "iso8601" } ],
      "metadata": { "contract_version": "x.y.z", "seed": 123 }
    }
    ```

* **Status codes (typical):** `202` accepted, `400` invalid envelope, `401/403` auth, `409` duplicate/idempotent conflict, `429` rate limit.

---

### Internal AppServer (Node, internal-only)

* `POST /gh/{definition}:{version}/solve`

  * **Body:** **contracts/{definition}/{version}/inputs.schema.json**
  * **Success (200):** **contracts/{definition}/{version}/outputs.schema.json**
  * **Errors:**

    * `400` schema validation failed
    * `422` domain infeasible (e.g., violates constraints)
    * `429` busy / concurrency cap hit
    * `504` upstream timeout (compute engine didn’t respond in time)

> AppServer also enforces `manifest.json` (timeouts, vertex/sample caps) and `plugins.json` (runtime inventory match) before calling the compute engine.

---

### Message shape (API → queue)

> Sent by the Public API to the messaging fabric your Worker consumes from (e.g., Azure Service Bus queue/topic).

```json
{
  "job_id": "uuid",
  "tenant_id": "uuid",
  "app_id": "string",
  "definition": "{definition_name}",
  "version": "x.y.z",
  "inputs_hash": "sha256-hex",
  "payload": { /* contracts inputs */ },
  "requested_at": "iso8601"
}
```

**Required properties (headers/attributes are fine too):**

* `job_id`, `tenant_id`, `app_id`
* `definition`, `version`
* `inputs_hash` (for idempotency/short-circuiting)
* Optional routing: `priority`, `session_id` (e.g., per tenant), `retry_after`

---

### Worker behavior (queue consumer, internal)

1. **Receive** one message with a visibility/processing lock.
2. **Validate** `definition@version` + inputs against contracts; optionally **short-circuit** if a cached result exists for `inputs_hash`.
3. **Call AppServer** `/gh/{definition}:{version}/solve`.
4. **Persist** results and artifact metadata to the app database / object storage.
5. **Acknowledge**:

   * **Complete** on success.
   * **Abandon/Retry** on transient issues (backoff policy).
   * **Dead-letter** on poison/validation errors with a structured reason.

**Worker guardrails**

* **One active job per replica** (aligns with compute/license concurrency).
* **Lock renewal** for long runs.
* **Max delivery count** → dead-letter.
* **Correlation ID** flows from API → message → Worker → AppServer → compute engine.

---

### Optional: Preview fast lane, not queued (future MVP 2.0)

If you implement interactive sliders later:

* **WS/SSE** on API (or a small realtime gateway) → `POST /preview/{definition}:{version}` on AppServer.
* **Strict timebox & rate limits**; returns **small deltas** (e.g., transform + KPIs).
* **Batch “Apply/Save”** still goes through the queued **/jobs/run** path above.

---

**Key principles**

* **Contract-driven:** inputs/outputs strictly follow the versioned contracts.
* **Idempotent:** `inputs_hash` enables caching and duplicate collapse.
* **Separation of concerns:** Public API = auth/enqueue/status/result; Worker = compute; AppServer = validation + engine I/O.
* **Observability:** every hop logs `app_id`, `tenant_id`, `job_id`, `definition@version`, and `correlation_id`.

---

## 6) Data model (Supabase/Postgres)

Tables (minimum):

```sql
-- these are specific to single app use case (sitefit)
parcel(id uuid pk, geom geometry(Polygon,<EPSG>), attrs jsonb, tenant_id uuid)
house(id uuid pk, footprint geometry(Polygon,<EPSG>), entrance_edge int, attrs jsonb, tenant_id uuid)

-- these are shared across apps
job(id uuid pk, tenant_id uuid, app_id text,
    status text, priority int default 100,
    payload_json jsonb, attempts int default 0,
    started_at timestamptz, ended_at timestamptz,
    last_error jsonb, inputs_hash text,
    created_at timestamptz default now())

result(id uuid pk, job_id uuid fk, placement jsonb,
       kpis jsonb, score numeric, created_at timestamptz)
```

> Service Bus holds **messages**, not truth; Database remains the source for status/results.

---

## 7) Local dev (fast path)

* **AppServer** supports `USE_COMPUTE=false` (mock centroid); flip to true when Rhino.Compute is reachable.
* **Run locally** (example):

  ```bash
  # frontend
  pnpm -C apps/frontend dev
  # appserver (mock first)
  pnpm -C apps/appserver-node dev
  # api
  uvicorn apps/api-fastapi.main:app --reload --port 8081
  # worker
  uvicorn apps/worker-fastapi.main:app --reload --port 8082
  # db
  docker compose up postgres   # or Supabase local
  ```
* **Service Bus**: use a real SB namespace in dev or a thin in-memory shim (for unit tests).
* **Swap in real Rhino**: start Rhino.Compute on a Windows dev box; set `COMPUTE_URL` + `COMPUTE_API_KEY`.

---

## 8) Env vars (MVP)

**AppServer (Node)**

```
CONTRACTS_DIR=../contracts/sitefit/1.0.0
USE_COMPUTE=false
COMPUTE_URL=http://<rhino-dev-ip>/
COMPUTE_API_KEY=...
TIMEOUT_MS=240000
```

**API (FastAPI)**

```
DATABASE_URL=postgres://...
JWT_JWKS_URL=https://<supabase>.supabase.co/auth/v1/keys
BLOB_ACCOUNT=<name>
BLOB_SAS_SIGNING=<key or use MSI>
SERVICEBUS_NAMESPACE=<ns-name>
SERVICEBUS_QUEUE=<queue-name>
SERVICEBUS_CONN=<conn-string or use MSI>
APP_SERVER_URL=http://appserver.internal/gh/sitefit:1.0.0/solve
```

**Worker (FastAPI)**

```
DATABASE_URL=postgres://...
SERVICEBUS_NAMESPACE=<ns-name>
SERVICEBUS_QUEUE=<queue-name>
SERVICEBUS_CONN=<conn-string or use MSI>
APP_SERVER_URL=http://appserver.internal/gh/sitefit:1.0.0/solve
MAX_DELIVERY_COUNT=5
LOCK_RENEW_SEC=45
JOB_TIMEOUT_SEC=240
```

**Frontend**

```
NEXT_PUBLIC_API_BASE_URL=https://api.example.com
```

> In prod, mount secrets from **Key Vault** via **managed identity**, not `.env`.

---

## 9) Coding conventions

* **Type safety**: TypeScript strict in AppServer; Pydantic models in FastAPI.
* **Validation**: Ajv vs **contracts** in AppServer; Pydantic for API envelopes.
* **Geometry**: CRS explicit (`EPSG:*`); Worker normalizes to canonical meters CRS before calling AppServer.
* **Limits**: never call Rhino without checking `manifest.json` caps.
* **Errors**: standard taxonomy — `400` invalid schema, `422` infeasible/domain, `429` busy, `504` upstream timeout.

---

## 10) Observability

* Carry `x-correlation-id` end-to-end (Frontend → API → Worker → AppServer → Rhino).
* Metrics to watch:

  * **Service Bus**: queue depth, DLQ depth, abandon/complete rates.
  * **Jobs**: p95 runtime, success %, attempts.
  * **AppServer**: call latency, 429/504 rates.
  * **Rhino**: concurrency, timeouts.
* Logs ship to **Log Analytics** with `app_id`, `tenant_id`, `job_id`, `correlation_id`.

---

## 11) Security

* API is **public**; Worker & AppServer are **internal-only**.
* AppServer requires a **service token** (or mTLS) from Worker; **never** expose AppServer publicly.
* RhinoCompute behind **internal LB** only; requires **API key**.
* (Optional) Supabase DB reachable only from known **egress IP** (if NAT Gateway + allowlisting is used).
* Secrets in **Key Vault**; least-privilege RBAC; rotate keys.

---

## 12) Preview mode (future MVP 2.0)

* Add **WS/SSE** on API (or a small **Realtime Gateway**) → AppServer **`/preview/<def>:<ver>`**.
* AppServer returns **tiny deltas** (transform + KPIs) within ~800 ms.
* Keep batch/authoritative runs on the **Service Bus** path.
* Partition Rhino capacity: small dedicated **preview bucket** vs **batch bucket**.

---

## 13) Definition of Done (MVP Sitefit + platform)
* Contracts `sitefit/1.0.0` imported by API & AppServer.
* E2E works with **mock** → then with **real Rhino.Compute**:

  * `POST /placements/run` → `202 {job_id}`
  * Worker consumes **Service Bus** message → writes result
  * `/status` → `succeeded`, `/result` → placements + **GeoJSON**
* Blob SAS link returns a valid artifact; Vercel UI renders overlay.
* Correlation IDs visible in logs; SB retries/DLQ verified.

---

## 14) Quick tasks for Windsurf

* **AppServer**: scaffold `/gh/sitefit:1.0.0/solve` with Ajv + mock; add `USE_COMPUTE` switch.
* **API**: `/run`, `/status`, `/result`; implement **Service Bus producer**; write job metadata.
* **Worker**: **Service Bus consumer** (peek-lock + renewal) → call AppServer → write results → complete/abandon/DLQ.
* **Frontend**: minimal form → `run` → poll → draw parcel/house (SVG/Canvas).
* **Infra**: SB namespace+queue, ACA env, Blob, Key Vault, (Rhino VM for later).

---

## 15) Glossary

* **AppServer**: Node microservice that validates contracts and calls Rhino.Compute; internal-only.
* **Contracts**: JSON Schemas + manifest + bindings defining the Grasshopper API.
* **Rhino.Compute**: Headless Rhino/Grasshopper HTTP service on Windows.
* **SAS**: Shared Access Signature (time-limited Blob URL).
* **Peek-lock**: Message receive mode where the worker locks the message, processes, then completes/abandons.
* **DLQ**: Dead-letter queue for poison messages.

---
