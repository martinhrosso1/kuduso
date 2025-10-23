# Stage 2 — Messaging & Persistence (mock compute)

## Objectives

* Introduce **durable messaging** (enqueue from API, consume in Worker).
* Persist **job metadata** and **results** in Postgres/Supabase.
* Keep AppServer mocked; the Worker calls it.
* Preserve the same public API (`/jobs/run|status|result`) and frontend behavior.

**Success criteria**

* API returns `202 {job_id}`; Worker picks up the message, calls AppServer (mock), writes DB rows, and marks job `succeeded`.
* Retries work for transient failures; poison messages land in a dead-letter bucket.
* You can query status/result purely from the DB.

---

## 1) Data model (SQL)

Create minimal tables (works for Postgres or Supabase). Adjust names if you already created them.

```sql
-- 01_jobs.sql
create table if not exists job (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid,
  app_id text not null,
  definition text not null,
  version text not null,
  status text not null check (status in ('queued','running','succeeded','failed')),
  inputs_hash text not null,
  payload_json jsonb not null,                 -- validated + defaults applied
  attempts int not null default 0,
  last_error jsonb,
  priority int not null default 100,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  ended_at timestamptz
);

create index if not exists job_status_idx on job(status, created_at);
create index if not exists job_inputs_hash_idx on job(inputs_hash);

-- 02_results.sql
create table if not exists result (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references job(id) on delete cascade,
  outputs_json jsonb not null,
  score numeric,
  created_at timestamptz not null default now()
);

-- Optional: artifacts table if you want rows per artifact
create table if not exists artifact (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references job(id) on delete cascade,
  kind text not null,
  url text not null,
  expires_at timestamptz
);
```

**Notes**

* `payload_json` stores the **clean, validated** inputs your Worker will pass to AppServer.
* Keep artifacts in `outputs_json.artifacts` for MVP; split later only if needed.
* Supabase: add RLS later; for now, focus on the loop.

---

## 2) Message contract (API → Queue)

Define one **message shape**; store it next to contracts so all services import it.

```json
{
  "job_id": "uuid",
  "tenant_id": "uuid",
  "app_id": "string",
  "definition": "{definition_name}",
  "version": "x.y.z",
  "inputs_hash": "sha256-hex",
  "requested_at": "iso8601",
  "payload": { /* contracts/<def>/<ver>/inputs.schema.json */ },
  "priority": 100
}
```

**Headers/properties** to include when sending:

* `x-correlation-id`
* `attempt` (starts at 0; the queue may maintain delivery count too)
* `session_id` (optional, e.g., `tenant_id` if you later want ordered processing per tenant)

---

## 3) API changes (producer)

Replace the Stage-1 synchronous call with **DB write + enqueue**.

**Flow**

1. Validate envelope + `inputs` against `inputs.schema.json` (same as Stage 1).
2. **Materialize defaults** in `inputs` (important for hashing).
3. Compute `inputs_hash`.
4. **(Optional idempotency):** if an identical `inputs_hash` already has a `succeeded` result, short-circuit and return that `job_id`.
5. Insert `job` row with `status='queued'`.
6. **Send message** to the queue with the fields above.
7. Return `202 {job_id}`.

**Python (FastAPI) – producer sketch**

```python
# apps/api-fastapi/queue.py
import os, json, hashlib, uuid, datetime as dt
from azure.servicebus.aio import ServiceBusClient
from azure.servicebus import ServiceBusMessage

SB_CONN = os.getenv("SERVICEBUS_CONN")
SB_QUEUE = os.getenv("SERVICEBUS_QUEUE")

def norm_hash(inputs: dict, definition: str, version: str) -> str:
    s = json.dumps(inputs, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256((s + definition + version).encode()).hexdigest()

async def send_job(job, cid: str):
    payload = {
        "job_id": str(job["id"]),
        "tenant_id": str(job.get("tenant_id") or ""),
        "app_id": job["app_id"],
        "definition": job["definition"],
        "version": job["version"],
        "inputs_hash": job["inputs_hash"],
        "requested_at": dt.datetime.utcnow().isoformat() + "Z",
        "payload": job["payload_json"],
        "priority": job.get("priority", 100),
    }
    msg = ServiceBusMessage(
        body=json.dumps(payload),
        application_properties={"x-correlation-id": cid, "priority": payload["priority"]}
    )
    async with ServiceBusClient.from_connection_string(SB_CONN) as client:
        sender = client.get_queue_sender(SB_QUEUE)
        async with sender:
            await sender.send_messages(msg)
```

**DB insert (psycopg / SQLAlchemy)**

```python
job_id = uuid.uuid4()
await db.execute(
    """insert into job(id, tenant_id, app_id, definition, version, status, inputs_hash, payload_json)
       values (:id, :tenant_id, :app_id, :def, :ver, 'queued', :hash, :payload)""",
    {"id": job_id, "tenant_id": tenant_id, "app_id": app_id, "def": definition, "ver": version,
     "hash": inputs_hash, "payload": inputs_clean}
)
await send_job({...same fields...}, cid)
return {"job_id": str(job_id)}
```

**Status/Result endpoints** stay the same but now read from DB:

* `/jobs/status/{job_id}`: read `status`, `attempts`, `last_error`
* `/jobs/result/{job_id}`: join `result` by `job_id`

---

## 4) Worker (consumer) — with lock renewal

The Worker receives messages, calls the **mock AppServer**, persists results, and completes the message. Add **lock renewal** for runs that take longer than the initial lock.

**Python (FastAPI runner or plain script) – consumer sketch**

```python
# apps/worker-fastapi/runner.py
import asyncio, os, json, datetime as dt
from azure.servicebus.aio import ServiceBusClient
from azure.servicebus import ServiceBusMessage
import httpx
import asyncpg

SB_CONN = os.getenv("SERVICEBUS_CONN")
SB_QUEUE = os.getenv("SERVICEBUS_QUEUE")
APP_SERVER_URL = os.getenv("APP_SERVER_URL", "http://localhost:8080/gh/{def}:{ver}/solve")
DB_URL = os.getenv("DATABASE_URL")
LOCK_RENEW_SEC = int(os.getenv("LOCK_RENEW_SEC", "45"))
JOB_TIMEOUT_SEC = int(os.getenv("JOB_TIMEOUT_SEC", "240"))

async def process_message(session, message, pool):
    cid = (message.application_properties or {}).get(b"x-correlation-id", "").decode() or "no-cid"
    body = json.loads(str(message))
    job_id = body["job_id"]
    async with pool.acquire() as conn:
        # mark running, increment attempts
        await conn.execute(
            """update job set status='running', attempts=attempts+1, started_at=now()
               where id = $1""", job_id
        )
    # call AppServer (mock)
    url = APP_SERVER_URL.format(def=body["definition"], ver=body["version"])
    try:
        async with httpx.AsyncClient(timeout=JOB_TIMEOUT_SEC) as client:
            # lock renewal task
            async def renew():
                while True:
                    await asyncio.sleep(LOCK_RENEW_SEC)
                    try:
                        await session.renew_message_lock(message)
                    except Exception:
                        break
            renew_task = asyncio.create_task(renew())

            resp = await client.post(url, json=body["payload"], headers={"x-correlation-id": cid})
            renew_task.cancel()

        if resp.status_code != 200:
            raise RuntimeError(f"AppServer {resp.status_code}: {resp.text}")

        outputs = resp.json()
        async with pool.acquire() as conn:
            await conn.execute(
                "insert into result(job_id, outputs_json, score) values ($1, $2, $3)",
                job_id, json.dumps(outputs), outputs.get("results", [{}])[0].get("score")
            )
            await conn.execute(
                "update job set status='succeeded', ended_at=now(), last_error=null where id=$1",
                job_id
            )
        await session.complete_message(message)
    except Exception as e:
        async with pool.acquire() as conn:
            await conn.execute(
                "update job set status='failed', ended_at=now(), last_error=$2 where id=$1",
                job_id, json.dumps({"message": str(e)})
            )
        # Rely on queue retry policy:
        await session.abandon_message(message)

async def main():
    pool = await asyncpg.create_pool(dsn=DB_URL, min_size=1, max_size=2)
    async with ServiceBusClient.from_connection_string(SB_CONN) as client:
        receiver = client.get_queue_receiver(queue_name=SB_QUEUE, max_wait_time=5)
        async with receiver:
            while True:
                messages = await receiver.receive_messages(max_message_count=1)
                if not messages: continue
                for m in messages:
                    async with receiver:
                        await process_message(receiver, m, pool)

if __name__ == "__main__":
    asyncio.run(main())
```

**Behavior**

* Updates job to `running`, increments `attempts`.
* Calls AppServer (mock).
* Writes `result` row; marks job `succeeded`.
* On error: writes `failed` and `last_error`, **abandons** the message (queue applies retry/backoff). After max deliveries, the broker dead-letters it.

---

## 5) Retry, DLQ, and idempotency

* **Retry policy**: set **max delivery count** (e.g., 5). The queue handles backoff; your Worker just **abandons** on transient errors.
* **DLQ**: when a message exceeds max deliveries or you explicitly dead-letter, it goes to the dead-letter sub-queue. Add a tiny admin script later to **peek/repair/replay**.
* **Idempotency**:

  * API computes `inputs_hash` and stores it in `job.inputs_hash`.
  * (Optional) Before processing, the Worker can check if a `succeeded` result with the same `inputs_hash` already exists and **short-circuit** (update job to reuse that result) to avoid recompute.
  * Always pass the same `payload` forward (defaults materialized), so hashing is stable.

---

## 6) Observability (local)

* **Correlation ID**: API generates or propagates `x-correlation-id`; publish it as a message property; Worker forwards to AppServer.
* **Logs**: print structured JSON lines with `cid, job_id, status, attempt, definition@version`.
* **Counters** (even simple printouts now): messages received, completed, abandoned; avg mock latency.

---

## 7) Local run & dev ergonomics

* Use a **real** Service Bus namespace for dev (no official emulator). For unit tests you can stub `send_job`/`receive_messages`.
* Docker Compose (optional) for Postgres:

  ```yaml
  services:
    db:
      image: postgis/postgis:16-3.4
      ports: ["5432:5432"]
      environment: { POSTGRES_PASSWORD: postgres, POSTGRES_USER: postgres, POSTGRES_DB: housefit }
  ```
* Env vars:

  ```
  DATABASE_URL=postgres://postgres:postgres@localhost:5432/housefit
  SERVICEBUS_CONN=Endpoint=sb://...;SharedAccessKeyName=...;SharedAccessKey=...;
  SERVICEBUS_QUEUE=housefit-jobs
  APP_SERVER_URL=http://localhost:8080/gh/{def}:{ver}/solve
  LOCK_RENEW_SEC=45
  JOB_TIMEOUT_SEC=240
  ```

**Run order (3 terminals)**

1. **AppServer (mock)**: `pnpm -C apps/appserver-node dev`
2. **API**: `uvicorn apps/api-fastapi.main:app --reload --port 8081`
3. **Worker**: `python apps/worker-fastapi/runner.py`
4. **Frontend**: `pnpm -C apps/frontend dev` (optional; you can just hit the API)

---

## 8) Tests (e2e with queue)

* **Happy path**: POST `/jobs/run` → poll `/jobs/status` until `succeeded` → GET `/jobs/result` validates against `outputs.schema.json`.
* **Retry path**: make AppServer fail once (e.g., env `FAIL_ONCE=true`) → Worker abandons → second delivery succeeds.
* **DLQ path**: force repeated failures → message lands in DLQ; job ends `failed` with `last_error`.

Tip: mark these “slow” and separate from unit tests.

---

## 9) Security & secrets (dev level)

* Keep connection strings in `.env` (dev only).
* Stage 3 will move secrets to **Key Vault** and services to **managed identity**.

---

## 10) Exit checklist (Stage 2)

* [ ] API writes `job` row (queued), **enqueues** a message, and returns `202 {job_id}`.
* [ ] Worker **receives → calls mock AppServer → writes `result` → completes** the message.
* [ ] `/jobs/status` and `/jobs/result` read from DB and work reliably.
* [ ] Retries observed (abandon once, then succeed); DLQ observed for poison.
* [ ] Correlation IDs flow through logs; minimal metrics visible (counts/timings).
* [ ] Frontend behavior unchanged (button → status → result).

---

## 11) What’s next (why Stage 3 will be easy)

* Swapping to cloud is mostly **infra**: ACA, Service Bus namespace, Blob SAS, Key Vault.
* **Code** paths don’t change: API still enqueues and reads DB; Worker still consumes and calls AppServer; AppServer is still a black box (will flip from mock to Rhino in Stage 4).

That’s Stage 2 in depth—durable, observable, and still fast to iterate locally while staying aligned with the final architecture.
