# Stage 3 — **Messaging & Persistence (cloud-backed, still mocked compute)** 

# 3.1 What changes now (at a glance)

* **API** stops doing in-memory storage / sync compute. It now:

  1. Validates and **materializes defaults**.
  2. Inserts a `job` row in **Supabase** (`status='queued'`).
  3. **Enqueues** a message to **Azure Service Bus**.
  4. Returns `202 {job_id}`. Status/result endpoints read from **Supabase**.

* **Worker** starts consuming the queue:

  1. **Peek-lock** + **lock renewal** during compute.
  2. Calls **AppServer (mock)**.
  3. Writes `result` to **Supabase**, **completes** the message.
  4. Abandons on transient; **DLQs** poison.

* **Artifacts**: API generates **Blob SAS** URLs for big outputs and stores refs in DB.

* **Observability**: consistent **correlation IDs** and job metadata in logs; KEDA scales the Worker on queue depth.

---

# 3.2 Configuration (env & secrets)

Set via ACA env (most values come from **Key Vault** refs you created in Stage 2):

**API (FastAPI)**

```
DATABASE_URL=secretref:DATABASE-URL
SERVICEBUS_CONN=secretref:SERVICEBUS-CONN         # (RBAC/MI later)
SERVICEBUS_QUEUE=jobs-<app_id>
APP_SERVER_URL=http://aca-appserver.internal/gh/{def}:{ver}/solve
JWT_JWKS_URL=https://<supabase>.supabase.co/auth/v1/keys
BLOB_ACCOUNT=<storage-account-name>
BLOB_SAS_SIGNING=secretref:BLOB-SAS-SIGNING       # account key or use MI→user delegation SAS later
RESULT_CACHE_TTL=300
```

**Worker (FastAPI)**

```
DATABASE_URL=secretref:DATABASE-URL
SERVICEBUS_CONN=secretref:SERVICEBUS-CONN
SERVICEBUS_QUEUE=jobs-<app_id>
APP_SERVER_URL=http://aca-appserver.internal/gh/{def}:{ver}/solve
LOCK_RENEW_SEC=45
JOB_TIMEOUT_SEC=240
MAX_ATTEMPTS=5
```

**AppServer (Node, still mock)**

```
USE_COMPUTE=false
CONTRACTS_DIR=/contracts/<def>/<ver>
TIMEOUT_MS=240000
```

---

# 3.3 Supabase schema (minimal, normalized enough)

> You can create these via SQL migrations (Alembic/Flyway). Keep RLS simple for now; enforce tenancy later.

```sql
-- job state
create table if not exists job (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid,
  app_id text not null,
  definition text not null,
  version text not null,
  status text not null check (status in ('queued','running','succeeded','failed')),
  inputs_hash text not null,
  payload_json jsonb not null,                 -- materialized defaults
  attempts int not null default 0,
  priority int not null default 100,
  last_error jsonb,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  ended_at timestamptz
);

create index if not exists job_status_idx on job(status, created_at);
create index if not exists job_inputs_hash_idx on job(inputs_hash);

-- result payload
create table if not exists result (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references job(id) on delete cascade,
  outputs_json jsonb not null,
  score numeric,
  created_at timestamptz not null default now()
);

-- optional per-artifact rows; you can also keep inside outputs_json.artifacts
create table if not exists artifact (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references job(id) on delete cascade,
  kind text not null,
  url text not null,
  expires_at timestamptz
);
```

---

# 3.4 Message contract (API → Service Bus)

Keep it next to contracts for reuse:

```json
{
  "job_id": "uuid",
  "tenant_id": "uuid",
  "app_id": "string",
  "definition": "{definition_name}",
  "version": "x.y.z",
  "inputs_hash": "sha256-hex",
  "requested_at": "iso8601",
  "payload": { /* inputs.schema.json (defaults applied) */ },
  "priority": 100
}
```

Set properties/headers too:

* `x-correlation-id`
* optional: `session_id` (e.g., tenant), `attempt`

---

# 3.5 API changes (producer)

### 1) Validate + materialize defaults

* Load `inputs.schema.json` and validate.
* Apply defaults so **hashing & caching** are stable.

```python
normalized = json.dumps(inputs_with_defaults, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
inputs_hash = sha256((normalized + definition + version).encode()).hexdigest()
```

### 2) Insert job row

```sql
insert into job (id, tenant_id, app_id, definition, version, status, inputs_hash, payload_json)
values (:id, :tenant_id, :app_id, :def, :ver, 'queued', :hash, :payload_json);
```

### 3) Enqueue message

Use the SB connection string for now (Stage 2 secrets). Put `x-correlation-id` into application properties.

### 4) Return `202 {job_id}`

* Status/Result endpoints now **read from DB** (not in-memory).

### 5) Artifacts (SAS)

Add a helper to mint **time-boxed SAS** for blobs (or user-delegation SAS w/ MI later). Store `kind,url,expires_at` in `outputs.artifacts` or `artifact` table.

**Status endpoints**

* `/jobs/status/{job_id}` → `{status, attempts, last_error?}`
* `/jobs/result/{job_id}` → `result.outputs_json` (already matching `outputs.schema.json`)

**Error taxonomy**

* `400` schema invalid (inputs)
* `401/403` auth
* `409` idempotency collision (optional)
* `429` rate limit
* `5xx` infra issues (SB, DB)

---

# 3.6 Worker changes (consumer)

**Loop**

1. Receive (peek-lock) **1 message**.
2. `update job set status='running', attempts=attempts+1, started_at=now()`.
3. Start a **lock renewal** task (every `LOCK_RENEW_SEC`).
4. `POST` to AppServer mock endpoint:

   * URL: `APP_SERVER_URL.format(def, ver)`
   * Headers: `x-correlation-id` from message props
   * Body: `payload`
5. On success:

   * `insert into result(job_id, outputs_json, score)` (extract score if you have one)
   * `update job set status='succeeded', ended_at=now(), last_error=null`
   * `complete` the message
6. On transient error (HTTP 429/502/timeout):

   * `update job set status='failed', last_error=...` (optional intermediate status), **abandon** message (SB will redeliver)
7. On poison/validation error:

   * **dead-letter** with a structured reason → `last_error` with details

**Guardrails**

* **One active job per replica** (process serially).
* Respect **`JOB_TIMEOUT_SEC`**.
* Keep **attempts** in DB aligned with SB **delivery count** for debugging.

---

# 3.7 KEDA autoscale (already in Stage 2 infra)

Worker scales by `messageCount` on your queue:

* `min_replicas = 0`, `max_replicas = N` (≤ Rhino seats when you flip to real compute).
* Threshold: start with `5` messages/replica; tune later.

---

# 3.8 Observability (logs & metrics)

**Log these consistently (JSON lines are fine):**

* `cid` (x-correlation-id)
* `job_id`, `app_id`, `tenant_id`
* `definition@version`
* API: `event="enqueue"`, DB write timings, SB send duration
* Worker: `event="claim"|"call_appserver"|"persist"|"complete"|"abandon"|"deadletter"`, latency buckets
* AppServer: `event="solve.start|solve.done"`, validation errors

**Dashboards (Log Analytics)**

* SB queue length & DLQ depth
* Worker replica count
* Job p50/p95 runtime
* AppServer latency + error codes

---

# 3.9 Testing plan (must pass)

**Happy path**

1. `POST /jobs/run` with a valid example → `202 {job_id}`
2. Worker scales (0→1), processes message
3. `/jobs/status/{id}` → `succeeded` within seconds
4. `/jobs/result/{id}` validates against `outputs.schema.json`
5. Artifact SAS URL works (if any)

**Retry path**

* Flip AppServer to return `429` once (env flag).
* Worker abandons → message redelivered → succeeds on next attempt.

**Poison path**

* Send invalid payload (passes API but fails in AppServer domain validation → `422`).
* Worker **dead-letters**; `/jobs/status` shows `failed`; DLQ has message with reason.

**Idempotency (optional now)**

* Submit same inputs twice (same `inputs_hash`) → second `run` short-circuits to existing result or returns same `job_id`.

---

# 3.10 Rollout checklist

* API container has **Key Vault** secret refs resolved (DB, SB, SAS key).
* Worker has SB & DB connectivity; can resolve **AppServer internal FQDN**.
* AppServer (mock) reachable from Worker; returns 200.
* SB queue **max delivery count** set (e.g., 5); DLQ enabled.
* Frontend configured with `NEXT_PUBLIC_API_BASE_URL` of API.

---

# 3.11 Security & tenancy (minimums right now)

* API verifies **Supabase JWT** on `/jobs/run` and stamps `tenant_id`.
* CORS limited to Vercel domains.
* AppServer & Worker **internal-only** ingress.
* No public exposure of Rhino (still offstage); mock compute only.
* Secrets only in **Key Vault**.

---

# 3.12 What you don’t change yet

* No real Rhino call—**keep `USE_COMPUTE=false`**.
* No private networking to Rhino yet (that’s Stage 4/5 when you move to ILB/VMSS).
* No fancy preview/realtime path—batch only.

---

## TL;DR

Wire your code to **Supabase** + **Service Bus** you created in Stage 2: API enqueues + writes DB; Worker consumes + calls **mock AppServer** + persists result; artifacts use **Blob SAS**. Add solid logs with correlation IDs. When these tests pass, you have a cloud-backed pipeline ready to flip `USE_COMPUTE=true` in Stage 4 with zero API changes.
