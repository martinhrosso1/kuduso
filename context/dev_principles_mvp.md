# MVP development Principles (the “10 rules”)

1. **One deployable per concern:** `web`, `api`, `worker`. No shared code without a tiny `packages/core` lib.
2. **Two environments max:** `dev` and `prod`. Staging only if you truly need it.
3. **Build once, deploy twice:** Same artifact → dev/prod. No env-specific code paths.
4. **Env vars only:** `.env.local` for dev, real secrets in Key Vault/Env vars in prod. Never commit secrets.
5. **Tests that matter:** A few fast unit tests + 1 happy-path e2e per user journey. Stop there.
6. **Basic observability:** Structured logs, request IDs, `/healthz` endpoint, and error tracking (e.g., Sentry). Dashboards later.
7. **Contracts light:** OpenAPI for your API, JSON Schema for any queue/job payloads. Backward-compatible changes only.
8. **Idempotency on writes:** Accept idempotency keys for POST/PUT that cause side effects.
9. **Queues for “slow”:** Anything >300–500 ms → background job with a retry policy.
10. **Feature toggles:** Use a simple env flag or config switch. Canary/blue-green can wait.

# Tiny Tooling (day-1)

* **Pre-commit:** Black, isort, Flake8 (py), Prettier + ESLint (ts).
* **Type checks:** mypy (py) + tsc (ts) — *non-blocking at first*, flip to blocking later.
* **Security (quick):** pip-audit/npm audit in CI. That’s it.

# Makefile (copy/paste)

```makefile
.PHONY: dev test lint fmt api web worker
dev: ## run everything locally
\tuvicorn apps.api.main:app --reload &
\tnpm --prefix apps/web run dev
test:
\tpytest -q && npm --prefix apps/web test -s
lint:
\tflake8 && mypy || true && npm --prefix apps/web run lint
fmt:
\tblack . && isort . && npm --prefix apps/web run format
```

# Minimal Testing You Actually Do

* **Unit:** services/helpers with no IO (fast).
* **Integration:** 1 test per external integration (DB/Stripe/Supabase).
* **E2E:** 1 spec per core flow (signup → first success action). Run on PR with a lightweight seed DB.

# Observability “just enough”

* **Logging:** JSON logs, request_id in middleware; include duration, status, route.
* **Health:** `/healthz` (deps optional) + `/readyz` (deps required).
* **Errors:** Sentry SDK in web/api/worker (dsn from env).

# API & Data Contracts (MVP)

* **OpenAPI auto-gen** from FastAPI; publish as artifact in CI.
* **JSON Schema** for queue/job payloads in `packages/core/schemas`.
* **Version in headers:** `X-API-Version: 0` (bump when breaking).

# Delivery (simple + safe)

* **Branching:** trunk + short feature branches.
* **CI:** install → lint → test → build → upload artifact.
* **CD:** dev auto-deploy on main; prod manual approval. Rollback = redeploy previous artifact.

# Data Discipline (MVP)

* **Migrations:** Alembic only forward (expand → backfill → switch). Avoid destructive changes early.
* **Seeds:** one deterministic seed script for dev/e2e.