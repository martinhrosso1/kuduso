# Stage 5 — Hardening & Guardrails

Below is a concrete, “do-this-now” hardening plan covering limits, safety rails, security, reliability, and ops. It’s written for your stack (ACA + Service Bus + Supabase + Blob + AppServer + Rhino.Compute).

---

# 5.1 Contracts & validation (stop bad inputs early)

**What to add**

* **Strict JSON Schema**: every field typed, min/max, regex for CRS (`^EPSG:\d+$`), polygon ring rules (closed, no self-intersections).
* **Default materialization**: API expands defaults before hashing/enqueueing.
* **Domain validation layer** in AppServer (pre-compute):

  * Planarity, polygon orientation, max vertices (e.g., 5k), parcel area cap (e.g., 50k m²).
  * Reject obviously degenerate inputs (zero area, NaNs, CRS mismatch).

**Outcomes**

* API returns **400** (schema) or **422** (domain) without waking Worker/Rhino.
* Clear error JSON (`code`, `message`, `field`, `hint`).

---

# 5.2 Runtime caps (keep the box safe)

**In `manifest.json`** (per definition/version):

```json
{
  "timeout_sec": 120,
  "max_vertices": 5000,
  "max_samples": 200,
  "max_area_m2": 50000,
  "max_artifact_mb": 20
}
```

**Enforcement**

* AppServer checks caps **before** calling Compute.
* AppServer enforces **wall-clock** timeout (AbortSignal) and **concurrency** (semaphore).
* Worker has **JOB_TIMEOUT_SEC** slightly > manifest timeout (e.g., 150s).

**HTTP codes**

* `429` when AppServer queue is saturated (no seat available).
* `504` when timeout reached (AppServer cancels upstream call).

---

# 5.3 Concurrency & backpressure (protect Rhino seats)

**Seat budget**

* Seats = number of Rhino workers; start with 1 on single VM.
* AppServer: `const SEM = new Semaphore(SEATS);` acquire per solve.
* Reject quickly when queue is full:

  * **Try-acquire** with small wait (e.g., 100–250 ms). If not, return `429` with `retry_after`.

**Worker settings**

* 1 job per replica.
* KEDA threshold tuned so **replicas ≤ seats** once you go real compute (or add a second throttle in Worker that defers if AppServer declines).

---

# 5.4 Retry policy & DLQ (make failures boring)

**Transient (retryable)**

* SB/network hiccup, AppServer `429/502/503/504`.
* Action: **abandon** message → SB redelivery (exponential backoff in Worker or rely on SB visibility timeout). Persist last error in DB.

**Permanent (poison)**

* API `400`, AppServer `422` (domain), plugin mismatch, impossible geometry.
* Action: **dead-letter** with structured reason and copy to DB; **don’t retry**.

**Queue config**

* `max_delivery_count`: 5 (then DLQ).
* Add a tiny **DLQ peek & replay** admin endpoint/tool (replay only if transient cause is resolved).

---

# 5.5 Idempotency & dedup (save money)

**API side**

* Compute `inputs_hash` from **normalized inputs + definition + version**.
* On `/jobs/run`, check for **recent success** with same hash:

  * If found and still valid → return existing `job_id` (or `result_id`).
  * Else create a new job.

**Worker side**

* When writing results, use **upsert** on `(job_id)` to avoid double write on retries.

---

# 5.6 Storage discipline (artifacts & limits)

**Artifacts**

* Don’t inline big geometry. Upload to Blob and return **SAS** in `artifacts[]`.
* Cap artifact size: refuse > `max_artifact_mb` with `413 Payload Too Large` from AppServer/API.

**Lifecycle**

* Blob policy: e.g., delete artifacts after **30 days** in dev, **90** in prod (tier to Cool first).
* DB retention: keep `job/result` for 180–365 days, but trim verbose debug columns.

---

# 5.7 Security hardening (least privilege everywhere)

**Network**

* AppServer & Worker: **internal ingress** only.
* Rhino.Compute: **no public IP** in prod; behind **Internal Load Balancer**; only AppServer subnet can reach.
* Private endpoints (later): Storage, Service Bus (if you go all-private).

**Secrets**

* Only in **Key Vault**. ACA uses **KeyVaultRef**; rotate keys on a schedule.
* Prefer **Managed Identity** over connection strings (SB Premium/RBAC; Blob user-delegation SAS).

**AuthN/AuthZ**

* API verifies **Supabase JWT**; stamp `tenant_id`.
* Column-level RLS (later): ensure tenant rows are isolated.
* Rate limit on `/jobs/run` per `tenant_id` (e.g., 30/min burst 60).

---

# 5.8 Observability SLIs/SLOs & alerts (see issues before users do)

**SLIs**

* Job latency (enqueue→succeeded) p50/p95.
* AppServer solve latency p50/p95.
* Service Bus queue length & DLQ depth.
* Error rate by class (4xx schema/domain vs 5xx transient).
* Compute seat utilization (AppServer semaphore occupancy).

**SLOs (initial)**

* p95 job latency < 10s (mock) / < 30s (real compute, small graphs).
* Error budget: < 0.5% 5xx over 7 days.
* DLQ depth = 0 for last 24h.

**Alerts**

* Queue length > 100 for 5 min.
* DLQ depth > 0.
* AppServer `429` rate > 5% for 5 min.
* p95 solve time doubles vs baseline.
* Rhino health endpoint failing.

---

# 5.9 Health checks & readiness

**API**

* `/livez` (always 200 if process up).
* `/readyz` checks: DB reachable, SB send test (or cached), KV secret resolved.

**Worker**

* `/readyz` true only if SB can receive; refuses readiness while backlog > X and no seats (optional).

**AppServer**

* `/readyz` runs:

  * KV secrets loaded,
  * (optional) plugin attestation vs `plugins.json`,
  * (optional) warm ping to Compute `/version`.

Use ACA **probe** settings so non-ready revisions don’t get traffic.

---

# 5.10 Release safety (no drama deploys)

* **Revisions** in ACA: deploy new image as a new revision; run smoke; then shift traffic.
* **Feature flags**:

  * `USE_COMPUTE` per definition/version.
  * “Return 429 once” flag for retry tests.
* **Blue/green for Rhino**:

  * Keep `1.0.0` and `1.0.1` side-by-side on disk.
  * Flip `bindings.json` version only after sync & attestation OK.

---

# 5.11 Cost controls (stop silent creep)

* Worker `min_replicas=0`.
* AppServer can be `min=0` off-hours (accept cold start) in dev.
* Log Analytics retention 30–45 days; daily cap.
* Storage lifecycle: Cool → Delete.
* SB Standard is fine until MI/RBAC is needed.

---

# 5.12 Data protection & compliance (baseline)

* Log **no raw personal data**; mask tokens, SAS, secrets.
* Store only necessary geometry; clear old runs with lifecycle.
* GDPR: give tenants an erase endpoint that deletes rows + blobs for a job.

---

# 5.13 Chaos & load tests (confidence builders)

* **Retry drill**: force AppServer to 429 once per job; confirm Worker retries.
* **Timeout drill**: make GH sleep > `timeout_sec`; confirm `504` and no runaway process.
* **Burst test**: enqueue 200 small jobs; verify p95 and no DLQ.
* **Node loss**: reboot Rhino VM; confirm API returns 503 and recovers; no job loss.

---

# 5.14 Runbooks (copy into your wiki)

**Queue stuck**

* Check SB metrics; if DLQ>0 inspect reason. If transient, replay; if poison, fix inputs or contract.
* Temporarily scale Workers to 0, clear a bad revision, scale back.

**Rhino down**

* AppServer `/readyz` failing; return 503. Restart Rhino service/IIS. If persistent, flip `USE_COMPUTE=false` for that definition to keep API responsive.

**Key rotation**

* Upload new secret to KV as `-v2`; update env var name via ACA revision; shift traffic; delete `-v1`.

**High 429**

* Increase seats (VMSS) or reduce KEDA max replicas; verify AppServer semaphore matches seat count.

---

# 5.15 Concrete items to implement now

* [ ] Add **schema/domain** validators with precise errors.
* [ ] Implement **semaphore** + **try-acquire** + `429` in AppServer.
* [ ] Enforce **manifest caps** and **timeout** with abortable HTTP to Compute.
* [ ] Worker: unify retry taxonomy (transient → abandon; poison → DLQ).
* [ ] **Idempotency** by `inputs_hash` (API short-circuit, Worker upsert).
* [ ] Blob **lifecycle** and `max_artifact_mb`.
* [ ] **Rate limit** `/jobs/run` per tenant.
* [ ] Health checks (`/livez`, `/readyz`) for all services.
* [ ] SLI dashboards & alerts (queue, DLQ, p95, 429%).
* [ ] Runbooks: queue stuck, Rhino down, rotate keys, replay DLQ.

---

## TL;DR

Stage 5 wires in **limits, retries, timeouts, concurrency control, idempotency, and security** so a bad input or noisy neighbor can’t take down Rhino or your API. You’ll know when things degrade (alerts), you’ll fail fast and clearly (HTTP taxonomy), and you’ll recover automatically (retries, DLQ). After this, you’re safe to scale users and definitions.
