Awesome—here’s a pragmatic, step-by-step roadmap from “empty repo” to a **working MVP**, tailored to your architecture (Vercel → API/Worker on ACA → Service Bus → internal AppServer → Rhino.Compute → Supabase + Blob). Each stage has: **goal**, **what you build**, and **exit criteria**.

---

# Stage 0 — Bootstrap & Contracts

**Goal:** Align on interfaces before code drifts.

**Build**

* Monorepo skeleton (`contracts/`, `apps/`, `infra/`).
* First **definition@version** in `contracts/{def}/{ver}` with:

  * `inputs.schema.json`, `outputs.schema.json`, `manifest.json`, `bindings.json`, `plugins.json`.
* Tiny **example payloads** in `contracts/.../examples/`.

**Exit criteria**

* Schemas validate with a script.
* Everyone can explain inputs/outputs from the contracts alone.

---

# Stage 1 — Mocked Compute Loop (local)

**Goal:** End-to-end JSON roundtrip without Rhino.

**Build**

* **AppServer (Node)**: `/gh/{def}:{ver}/solve` with Ajv validation + **mock** response.
* **API (FastAPI)**: `/jobs/run`, `/jobs/status/{id}`, `/jobs/result/{id}` (in-memory job table is fine for now).
* **Frontend (Next.js)**: simple form → call `/jobs/run` → poll → render results.

**Exit criteria**

* Clicking “Run” returns a result and draws basic geometry/KPIs.

---

 Stage 2 — **Cloud Infrastructure (OpenTofu/Terragrunt)** ✅ (new order)

**Goal:** Stand up the **platform** and **per-app** cloud resources now (dev env). Keep compute mocked for the moment.

**Build (IaC only; no code changes)**

* **Platform (shared) — one per env**

  * Resource Group, **ACR**, **Log Analytics**, **Key Vault**, **Storage (Blob)**, **Service Bus namespace**, **ACA environment**.
  * **Rhino Compute (dev)**: 1× Windows VM (public IP locked to your IP), API key; VMSS+ILB comes later.
  * **Shared AppServer (ACA)**: internal ingress; image deployed; `USE_COMPUTE=false` by default.
* **Per-app (sitefit)**

  * **Service Bus queue** for the app.
  * **API (ACA, external)** & **Worker (ACA, internal)** apps created (images deployed), but:

    * API still allowed to run in “local/mock mode” (sync call) until Stage 3,
    * Worker can be deployed but **paused** (min replicas 0) until Stage 3.
* **Supabase (DB + Auth)**

  * Create project (via TF provider or manually), capture `DATABASE_URL` and JWKS URL.
  * (Schema migrations remain in repo; don’t model tables in TF.)
* **Secrets**

  * Store **DATABASE_URL**, **SERVICEBUS_CONN** (or plan RBAC), **BLOB SAS signing key**, **COMPUTE_API_KEY** in **Key Vault**.
  * Grant **AcrPull** + **Key Vault Secrets User** to API/Worker/AppServer identities.
* **Repo/infra layout**

  * `infra/modules/{shared-core,shared-appserver,app-stack,rhino-vm}`
  * `infra/live/dev/{shared/{core,appserver,rhino},apps/sitefit}` with Terragrunt.

**Exit criteria**

* `terragrunt run-all apply` brings up ACR, KV, LAW, Storage, SB ns, ACA env, Rhino VM, AppServer, and app shells (API/Worker).
* API reachable over HTTPS; AppServer reachable internally.
* Secrets resolved from Key Vault; logs visible in Log Analytics.

---

# Stage 3 — **Messaging & Persistence (cloud-backed, still mocked compute)** ✅ (new order)

**Goal:** Replace local/in-memory bits with **Service Bus + Supabase**, using the infra from Stage 2. Keep AppServer’s **mock** solver.

**Build (code + config)**

* **API (producer)**

  * Validate envelope + inputs (materialize defaults).
  * Compute `inputs_hash`; write `job(status='queued', …)` to **Supabase**.
  * **Enqueue** message to **Service Bus** (`job_id`, `definition`, `version`, `inputs_hash`, payload, ids).
  * Return `202 {job_id}`; `/status` & `/result` read from **Supabase**.
* **Worker (consumer)**

  * **Peek-lock + lock renewal**; call **AppServer (mock)**; write `result` to **Supabase**; **complete** message.
  * Abandon on transient; DLQ on poison; 1 job/replica; **KEDA** scales on queue length.
* **Artifacts**

  * Implement real **Blob SAS** generation in API; store artifact refs in DB.
* **Observability**

  * Log `x-correlation-id`, `job_id`, `app_id`, `tenant_id`, `definition@version` across hops.

**Exit criteria**

* Enqueue → Worker consumes → DB has result → UI shows it; artifacts fetch via SAS.
* Retries work (abandon once, then succeed); DLQ holds poison messages.

---

# Stage 4 — Swap in Real Rhino.Compute (single node)

**Goal:** Replace mock with real Grasshopper.

**Build**

* Headless-safe **Grasshopper** file for the definition.
* **AppServer**: `USE_COMPUTE=true`, call Rhino.Compute `/grasshopper` using `bindings.json`.
* Verify `plugins.json` matches; add **plugin attestation** check.

**Exit criteria**

* Same API/UI as before—now powered by Rhino.
* A known input produces the expected placement/KPIs (golden test).

---

# Stage 5 — Hardening & Guardrails

**Goal:** Make it durable and safe.

**Build**

* **AppServer**: enforce `manifest.json` caps (timeout, max vertices, samples); return `400/422/429/504` consistently.
* **Worker**: one active job per replica; configure **max delivery count → DLQ**; add tiny DLQ peek/replay tool.
* **Idempotency**: API/Worker short-circuit on repeated `inputs_hash` (optional cache).
* **Security**: AppServer remains **internal-only**; Rhino behind **internal LB** ASAP; API CORS restricted.

**Exit criteria**

* Load test a small burst: API stays responsive; errors are categorized; DLQ contains bad messages.

---

# Stage 6 — Observability & Ops

**Goal:** See and operate the system.

**Build**

* Metrics: SB **queue depth/DLQ depth**, p95 job runtime, AppServer latency, Rhino timeouts.
* Dashboards & alerts on key thresholds (stuck queue, rising 429/504, error budget).
* Basic runbook: restart worker/appserver, rotate keys, replay DLQ.

**Exit criteria**

* A newcomer can diagnose “why is this job slow/failing?” in minutes.

---

# Stage 7 — Frontend UX Polish

**Goal:** MVP that users enjoy.

**Build**

* Better 2D/3D overlay; render artifacts (GeoJSON/glTF).
* Clear job states: queued/running/succeeded/failed with messages.
* Inline validation from `inputs.schema.json` (client-side).

**Exit criteria**

* Non-dev can complete a full run and understand the outcome.

---

# Stage 8 — Preview Lane (optional after MVP)

**Goal:** Live sliders without touching the batch path.

**Build**

* WS/SSE endpoint (in API or a tiny “realtime gateway”).
* **AppServer**: `/preview/{def}:{ver}` with strict timebox & rate limits; returns **deltas** (transform + KPIs).
* Reserve small Rhino capacity for preview; in-memory LRU cache keyed by discretized inputs.

**Exit criteria**

* 95% of preview calls < 800 ms; batch job latencies unaffected.

---

# Stage 9 — Multi-App Readiness (platform)

**Goal:** Reuse most of the infra for more apps.

**Build**

* Introduce **`app_id`** everywhere (messages, logs, DB rows, tags).
* Per-app **SB queue** (or topic subs), per-app policies in AppServer (caps/allowed defs).
* IaC module to stamp a new app: API, Worker, DB schema, frontend.

**Exit criteria**

* Creating a second app is a parameter change + one deploy.

---

## Cross-cutting checklists

**Definition of Done (each stage)**

* Contracts validate; unit tests for schema + examples.
* OpenAPI for API endpoints updated (even minimal).
* Logs include `app_id`, `tenant_id`, `job_id`, `correlation_id`, `definition@version`.

**Pitfalls to avoid**

* Long synchronous HTTP end-to-end—always enqueue for authoritative runs.
* Letting Workers process >1 job per replica—respect Rhino license seats.
* Big geometry payloads over the wire—ship deltas/KPIs; store heavy assets in Blob.

**When to scale out**

* SB queue length stays high → add Worker replicas (up to license cap).
* Rhino CPU stays pegged → add VM(s) and update the image; keep ILB.

---

### Bottom line

Start mocked, wire the real **Service Bus + DB + Blob** plumbing early, then flip to **Rhino.Compute** without changing interfaces. Harden, observe, and only then add the realtime preview and multi-app conveniences. This path ships a credible MVP fast while laying a platform you can extend.