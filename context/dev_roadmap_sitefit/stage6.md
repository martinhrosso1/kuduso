# Stage 6 — Observability & Ops

Stage 6 is where you make the system **observable, debuggable, and operable**. Below is a focused, practical blueprint tuned to your stack (ACA, Service Bus, Supabase, Blob, AppServer, Rhino.Compute).

---

# 6.1 Objectives

* You can answer quickly: *“Is it up? Is it slow? Why?”*
* One hop-to-hop **correlation ID** across API → SB → Worker → AppServer → Rhino.
* **Dashboards** for latency, errors, queue pressure, seat usage.
* **Actionable alerts** (few, high signal).
* **Runbooks** to fix the common failures.
* **Costs** and **log retention** under control.

---

# 6.2 Telemetry architecture (high level)

* **Logs & metrics** → Azure **Log Analytics** (Container Apps already wired).
* **Service metrics** (SB queue length/DLQ, ACA replica counts) → Azure Monitor.
* **(Optional, recommended)** Distributed tracing via **OpenTelemetry** (OTLP) → Azure Monitor / Application Insights.

---

# 6.3 Log schema & correlation

Adopt consistent, JSON-structured logs everywhere:

Common fields (all services):

```json
{
  "ts": "...", "level": "INFO|WARN|ERROR",
  "cid": "<x-correlation-id>", "job_id": "uuid",
  "tenant_id": "uuid", "app_id": "sitefit",
  "def": "sitefit", "ver": "1.0.0",
  "event": "enqueue|claim|call_appserver|persist|complete|abandon|deadletter",
  "duration_ms": 123, "status": "queued|running|succeeded|failed",
  "err_code": "SCHEMA|DOMAIN|TIMEOUT|UPSTREAM|RATE_LIMIT",
  "msg": "short human message"
}
```

* API generates `cid` (UUIDv4). Put it in:

  * HTTP response header `x-correlation-id`
  * SB application properties `x-correlation-id`
  * All child logs
* Worker copies message `cid` into all logs and to AppServer `x-correlation-id`.

**Don’t log secrets** (tokens, SAS, passwords). Mask long payloads; cap log size.

---

# 6.4 Metrics to collect (SLIs)

**API**

* Request rate, p50/p95/p99 latency
* Error rate split: 4xx schema/domain vs 5xx infra
* Queue publish latency (SB send ms)
* Result fetch latency

**Worker**

* Time in queue (enqueue→claim)
* Compute latency (call AppServer/Rhino)
* Success/abandon/dead-letter counts
* Attempts per job (mean/max)

**AppServer**

* Solve latency p50/p95/p99
* Rejection rate (`429` seat busy)
* Timeout rate (`504`)
* Concurrency gauge (current semaphore value / seats)

**Service Bus**

* Queue length, DLQ depth, active messages
* Delivery count histogram (how many retries)

**Rhino VM**

* CPU %, memory %, process up
* (Optional) IIS requests/sec & app pool restarts

**Storage**

* Blob egress (MB), artifact count per day

---

# 6.5 SLOs (initial targets)

* **Job p95 latency** (enqueue→succeeded):

  * Mock: < 10s, Real: < 30s (small graphs)
* **Availability** (API 2xx/3xx): ≥ 99.5%
* **Error budget** (5xx): ≤ 0.5% 7-day
* **DLQ depth**: = 0 steady state
* **429 rate (AppServer)**: < 5% 5-min window
  Document SLOs and wire **alerts** (below).

---

# 6.6 Dashboards (build these first)

Create in Azure Monitor / Workbooks using KQL:

1. **Executive overview**

   * API p95 latency, error rate
   * SB queue length & DLQ
   * Worker replicas (KEDA), success/abandon/DLQ
   * AppServer p95 solve, 429%, 504%
   * Rhino CPU %

2. **Job timeline**

   * Per `job_id`: enqueue time, claim time, compute duration, total latency

3. **Reliability**

   * Errors by class (SCHEMA/DOMAIN/UPSTREAM/TIMEOUT/RATE_LIMIT)
   * DLQ messages grouped by reason

4. **Capacity**

   * AppServer semaphore occupancy vs seats
   * Worker replicas vs queue length

5. **Cost-ish**

   * Blob artifact count & GB/day
   * Log ingestion GB/day

---

# 6.7 Alerts (few, high-signal)

Start with:

* **Queue congestion**: queue length > 100 for 5 min (sev2)
* **DLQ present**: DLQ depth > 0 for 5 min (sev2)
* **Latency regression**: API p95 > 2× baseline for 10 min (sev2)
* **Seat saturation**: AppServer 429% > 10% for 10 min (sev3)
* **Rhino down**: health probe failing for 3 min (sev1)
* **Error burst**: 5xx rate > 2% for 5 min (sev2)
* **Worker dead**: replicas = 0 while queue > 10 for 5 min (sev1)
* **Cost guard**: Log ingestion > planned daily cap (sev3)

Route to email/Teams; include runbook links.

---

# 6.8 KQL snippets (handy starters)

**API latency distribution**

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "aca-sitefit-api"
| extend j = todynamic(Log_s)
| where j.event == "request_end"
| summarize p50=percentile(todouble(j.duration_ms),50),
            p95=percentile(todouble(j.duration_ms),95),
            p99=percentile(todouble(j.duration_ms),99)
          by bin(TimeGenerated, 5m)
```

**Queue length vs worker replicas**

```kusto
AzureMetrics
| where ResourceProvider == "Microsoft.ServiceBus" and MetricName == "ActiveMessages"
| summarize qlen = avg(Total) by bin(TimeGenerated, 1m)
| join kind=leftouter (
    AzureMetrics
    | where ResourceProvider == "Microsoft.App" and MetricName == "ReplicaCount"
    | summarize replicas = avg(Total) by bin(TimeGenerated, 1m)
) on TimeGenerated
```

**DLQ reasons**

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "aca-sitefit-worker"
| extend j = todynamic(Log_s)
| where j.event == "deadletter"
| summarize count() by tostring(j.err_code), tostring(j.msg)
```

**End-to-end job latency**

```kusto
ContainerAppConsoleLogs_CL
| extend j = todynamic(Log_s)
| where j.job_id !~ "" and (j.event == "enqueue" or j.event == "complete")
| summarize first_enq=min(TimeGenerated), last_done=max(TimeGenerated) by j.job_id
| extend total_ms = datetime_diff('millisecond', last_done, first_enq)
| summarize p50=percentile(total_ms,50), p95=percentile(total_ms,95) by bin(first_enq, 5m)
```

---

# 6.9 Tracing (OpenTelemetry)

Add OTEL for **API** (FastAPI) and **AppServer** (Node):

* **API (Python)**: `opentelemetry-instrumentation-fastapi` + `Requests`
* **AppServer (Node)**: `@opentelemetry/sdk-node`, http/undici fetch instrumentation
* Propagate `traceparent` and carry `cid` as baggage; include SB message properties.
* Export OTLP → Azure Monitor (Application Insights).
  This gives click-through spans: API → SB publish → Worker → AppServer → HTTP to Rhino.

---

# 6.10 Health probes & synthetic checks

* **Liveness** `/livez`: process up.
* **Readiness** `/readyz`: dependencies reachable (DB, SB, KV).
* **Synthetic** every minute:

  * API `/readyz`
  * Tiny **enqueue→status** loop with a no-op definition (mock path) in dev/stage; ensure end-to-end path works.

---

# 6.11 Runbooks (link from alerts)

Create short, copyable steps:

**Queue backlog**

1. Check SB queue length & DLQ
2. Scale Worker up to N (≤ seats)
3. If AppServer 429% high → add seats or lower KEDA max
4. Investigate slow solves (AppServer p95)

**DLQ present**

1. Inspect reason JSON
2. If SCHEMA/DOMAIN → fix client or contracts
3. If UPSTREAM/TIMEOUT transient and fixed → replay DLQ tool

**Rhino down**

1. Check Compute `/version`, IIS pool status
2. Restart service; if persistent → flip feature flag `USE_COMPUTE=false` per def

**High 504/timeout**

1. Check manifest caps; reduce samples
2. Increase `timeout_sec` (small steps) or optimize GH

---

# 6.12 Cost & retention

* **Log Analytics** retention 30–45 days (dev), 90 (prod). Set daily ingestion cap.
* **Sampling**: keep INFO but drop verbose payloads; sample DEBUG at 1–5%.
* **Storage** lifecycle: artifacts Cool→Delete (30–90 days).
* **Compute**: ensure Worker min=0; AppServer min=1 (or 0 off-hours in dev).

---

# 6.13 Operational hygiene

* Versioned **dashboards & alerts** in Git (ARM/Workbook JSON).
* Tag everything with `env`, `app_id`, `owner`.
* Weekly **telemetry review**: regressions, noisy alerts, cost.
* Quarterly **chaos drills**: Rhino outage, SB outage, slow graph.

---

## TL;DR

Instrument API/Worker/AppServer with consistent **JSON logs + correlation IDs**, add **OTEL tracing**, build 4–5 **dashboards**, and wire a small set of **actionable alerts** (queue, DLQ, latency, seats, Rhino health). Add runbooks, synthetic checks, and retention/cost controls. With this, you’ll spot issues early, debug in minutes, and keep costs sane.
