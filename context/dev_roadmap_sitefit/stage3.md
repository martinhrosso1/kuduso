# Stage 3 — Minimal Cloud Deploy (prod-ish shape)

## Objectives

* **Platform (shared)**: ACR, Log Analytics, Key Vault, Service Bus **namespace**, Storage, **ACA environment**, **AppServer** (internal), and a temporary **Rhino VM**.
* **Per-app (sitefit)**: API (external), Worker (internal) with **KEDA** on **its own queue** in the shared namespace.
* Same endpoints as local: `/jobs/run | /jobs/status/{id} | /jobs/result/{id}`.
* Artifacts via **Blob SAS**. Secrets via **Key Vault**. Logs in **Log Analytics**.

Repo paths below match your structure:

```
kuduso/
  infra/
    modules/{shared-core,shared-appserver,app-stack,rhino-vm}
    live/dev/{shared/{core,appserver,rhino}, apps/sitefit}
```

---

## 0) Prereqs (one time)

* Azure subscription + CLI login.
* OpenTofu (or Terraform) + Terragrunt installed.
* **Supabase** (or Postgres) ready; you have a `DATABASE_URL`.
* Your three images build locally:

  * `shared/appserver-node`
  * `apps/sitefit/api-fastapi`
  * `apps/sitefit/worker-fastapi`

Tip: create an Azure **resource group & storage** for TF state once (outside Terragrunt) or reuse an existing one.

---

## 1) Build & push images → ACR (dev)

From repo root:

```bash
# 1) Build images (tag with Git SHA)
GIT_SHA=$(git rev-parse --short HEAD)

docker build -t appserver-node:$GIT_SHA ./shared/appserver-node
docker build -t sitefit-api:$GIT_SHA   ./apps/sitefit/api-fastapi
docker build -t sitefit-worker:$GIT_SHA ./apps/sitefit/worker-fastapi

# 2) Deploy CORE to get ACR endpoint first (see step 2), then login & push
```

You’ll push after **core** creates ACR.

---

## 2) Bring up the **platform core** (shared)

From `kuduso/infra/live/dev/shared/core`:

```bash
terragrunt init
terragrunt apply
```

**Outputs you’ll use**:

* `acr_server` (e.g., `kudusodevacr.azurecr.io`)
* `kv_name`
* `sb_namespace_name`
* `storage_account_name`
* `acaenv_id`
* `resource_group_name`

Now **push images**:

```bash
ACR=$(terragrunt output -raw acr_server)
az acr login -n ${ACR%%.*}

docker tag appserver-node:$GIT_SHA $ACR/appserver-node:$GIT_SHA
docker tag sitefit-api:$GIT_SHA   $ACR/api-fastapi:$GIT_SHA
docker tag sitefit-worker:$GIT_SHA $ACR/worker-fastapi:$GIT_SHA

docker push $ACR/appserver-node:$GIT_SHA
docker push $ACR/api-fastapi:$GIT_SHA
docker push $ACR/worker-fastapi:$GIT_SHA
```

---

## 3) Load secrets into **Key Vault** (shared)

Find KV name:

```bash
KV=$(terragrunt -chdir=../core output -raw kv_name)
```

Add secrets (replace values):

```bash
az keyvault secret set --vault-name $KV --name DATABASE-URL      --value "postgres://..."
az keyvault secret set --vault-name $KV --name SERVICEBUS-CONN   --value "Endpoint=sb://...;SharedAccessKey=..."
az keyvault secret set --vault-name $KV --name BLOB-SAS-SIGNING  --value "<account-key-or-user-delegation-tok>"
az keyvault secret set --vault-name $KV --name COMPUTE-API-KEY   --value "<rhino-compute-api-key>"
```

> Stage 3 uses a **connection string** for SB (simplest). Later you can switch to **RBAC/Managed Identity**.

---

## 4) Spin up **Rhino Compute** (temporary single VM)

From `kuduso/infra/live/dev/shared/rhino`:

```bash
export MY_IP=$(curl -s https://ifconfig.me)/32   # or hardcode your office / NAT IP
terragrunt init
terragrunt apply
```

**Outputs:**

* `public_ip` → build `COMPUTE_URL = http://<public_ip>:8081/`

On the VM:

* Install Windows updates, **Rhino 8**, and **Rhino.Compute**.
* Set the **API key** (matches KV `COMPUTE-API-KEY`).
* NSG already restricts ports `80/8081` to `MY_IP` (tighten as needed).

> Later you’ll swap this module to **VMSS + ILB** with no app changes.

---

## 5) Deploy **AppServer** (shared, internal)

From `kuduso/infra/live/dev/shared/appserver`:

```bash
export IMG_SHA=$GIT_SHA
export COMPUTE_URL="http://$(terragrunt -chdir=../rhino output -raw public_ip):8081/"
terragrunt init
terragrunt apply
```

Inputs (in `terragrunt.hcl`) include:

* `image = "<acr>/appserver-node:${IMG_SHA}"`
* `contracts_dir = "/contracts"` (or your exact subpath)
* `use_compute = false` (you can start `false` and toggle to `true` once smoke passes)
* `compute_url = $COMPUTE_URL`
* `compute_api_key_kv_secret_name = "COMPUTE-API-KEY"`

**What this does**

* Creates **aca-appserver** in the shared ACA env (internal ingress).
* Grants ACR pull + Key Vault secret read.
* Keeps AppServer **private**.

---

## 6) Deploy **sitefit app** (API + Worker + Queue)

From `kuduso/infra/live/dev/apps/sitefit`:

```bash
export IMG_SHA=$GIT_SHA
terragrunt init
terragrunt apply
```

This:

* Creates **Service Bus queue** `jobs-sitefit` in the **shared namespace**.
* Deploys **aca-sitefit-api** (external ingress) using image `<acr>/api-fastapi:$IMG_SHA`:

  * Env: `SERVICEBUS_QUEUE`, `APP_SERVER_URL`, `JWT_JWKS_URL`, `RESULT_CACHE_TTL`
  * Secrets (KV refs): `DATABASE_URL`, `SERVICEBUS_CONN`, `BLOB_SAS_SIGNING`
* Deploys **aca-sitefit-worker** (internal) using `<acr>/worker-fastapi:$IMG_SHA`:

  * KEDA scaler on `jobs-sitefit` length (`messageCount=5`)
  * 1 job / replica; `min=0, max=3` (cap to Rhino seats)
  * Lock renewal + timeout envs set from inputs

**Output to note**

* `api_fqdn` — the public host you’ll point the frontend to.

---

## 7) Frontend → API

For now, set your Next.js `.env` (Vercel or local) to:

```
NEXT_PUBLIC_API_BASE_URL=https://<api_fqdn>
```

(You can add DNS later; ACA’s hostname is fine for dev.)

---

## 8) Observability (already wired)

* Logs from all three ACA apps stream to **Log Analytics** created by **shared-core**.
* Start with simple KQL queries:

  * `ContainerAppConsoleLogs_CL | where ContainerAppName_s == "aca-sitefit-worker" | sort by TimeGenerated desc`
  * Track `x-correlation-id`, `job_id`, `definition@version`.

---

## 9) Smoke test (end-to-end)

1. **POST** `https://<api_fqdn>/jobs/run` with your **contracts/.../examples/valid/minimal.json** wrapped in the envelope:

   ```json
   {
     "app_id": "sitefit",
     "definition": "sitefit",
     "version": "1.0.0",
     "inputs": { ... }
   }
   ```

   Expect: `202 {"job_id": "<uuid>"}`

2. **Worker scales up** from 0 to 1 (watch in Azure Portal/Logs).

3. **GET** `/jobs/status/{job_id}` until `succeeded`.

4. **GET** `/jobs/result/{job_id}`:

   * Validates against `outputs.schema.json`.
   * If artifact URLs present, they are **SAS** and download.

5. **Retry path** (optional): set AppServer to return `429` once (env flag) → Worker abandons → SB retries → succeeds next attempt.

---

## 10) Security & guardrails (minimums for Stage 3)

* **AppServer & Worker**: internal-only ingress (already).
* **API**: CORS restricted to your Vercel domains; verify **Supabase JWT**.
* **Rhino VM**: NSG inbound limited to your IP(s); **API key** required by AppServer.
* **Secrets**: stored only in **Key Vault**; apps read via secret refs (no secrets in state or env files).
* **Scale caps**: worker `max_replicas` ≤ Rhino license seats; AppServer enforces `manifest` limits before calling Rhino.

---

## 11) Rollback, releases, and image updates

* All ACA apps use **revisions**. If a deploy misbehaves:

  * Shift traffic back to the previous revision (Portal or CLI).
* Release flow:

  1. Build & push images (`$GIT_SHA`).
  2. `export IMG_SHA=$GIT_SHA`
  3. `terragrunt apply` in `shared/appserver` (if AppServer changed).
  4. `terragrunt apply` in `apps/sitefit`.

---

## 12) Cost guardrails (dev)

* **Worker min=0**, max small.
* **AppServer min=1** (or 0 if you’re okay with cold start).
* **Log Analytics**: retention 30 days, daily cap if needed.
* **Storage**: Standard LRS; add lifecycle rule later for artifacts.

---

## 13) Common pitfalls (avoid these)

* **Forgetting defaults**: API must **materialize defaults** from `inputs.schema.json` before hashing / enqueueing.
* **Unbounded scale**: keep worker replicas capped and KEDA threshold sane (`messageCount=5–20`).
* **Secret injection**: don’t inline secrets in Terragrunt inputs; always write to KV and reference by name.
* **Direct AppServer exposure**: never give AppServer a public ingress; API/Worker call it internally only.

---

## 14) Exit criteria for Stage 3

* `terragrunt run-all apply` in `live/dev` brings up **shared core → rhino → appserver → sitefit** in order.
* Frontend calls **public API** and completes a run that writes to DB and (optionally) Blob.
* Logs show `x-correlation-id` end-to-end; queue depth & worker scaling visible.
* You can purposely trigger a retry and see it complete.

---

When this passes, you’re ready for **Stage 4**: flip `use_compute=true` on AppServer (if you started false), verify the real GH graph, and you’ve got a truly cloud-backed MVP.
