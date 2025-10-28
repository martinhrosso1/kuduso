# 🚀 Stage 3 Quick Start

Quick reference for setting up Stage 3 with Alembic migrations.

---

## Prerequisites

- ✅ Stage 2 infrastructure deployed
- ✅ Supabase account (free tier is fine)

---

## Step 1: Create Supabase Project (5 min)

1. Go to https://supabase.com → **New Project**
2. Settings:
   - Name: `kuduso-dev`
   - Password: **Generate & SAVE**
   - Region: `Europe West (eu-west-1)`
3. Wait ~2 minutes for provisioning

---

## Step 2: Get Connection String (1 min)

1. **Project Settings** → **Database**
2. **Connection string** → **URI** tab
3. Copy (looks like):
   ```
   postgresql://postgres.xxxxx:[YOUR-PASSWORD]@...
   ```
4. Replace `[YOUR-PASSWORD]` with actual password

---

## Step 3: Run Setup Script (3 min)

This will:
- Store secrets in Key Vault
- Install Alembic
- Run database migrations automatically

```bash
cd /home/martin/Desktop/kuduso
chmod +x STAGE3_SETUP.sh
./STAGE3_SETUP.sh
```

**When prompted**, paste your Supabase connection string.

The script will:
- ✅ Store `DATABASE-URL` in Key Vault
- ✅ Install Alembic + psycopg2
- ✅ Run migrations (`alembic upgrade head`)
- ✅ Store `SERVICEBUS-CONN` in Key Vault
- ✅ Store `BLOB-SAS-SIGNING` in Key Vault

---

## Step 4: Verify Database (1 min)

In Supabase → **Table Editor**, you should see:

- ✅ `job` - Job tracking
- ✅ `result` - Job results
- ✅ `artifact` - Blob artifacts
- ✅ `alembic_version` - Migration tracking

---

## ✅ Setup Complete!

You're ready to update the application code.

---

## Manual Migration (if needed)

If you need to run migrations manually:

```bash
cd apps/sitefit/migrations

# Install dependencies (one time)
pip install -r requirements.txt

# Set database URL
export DATABASE_URL="postgresql://postgres.xxxxx:..."

# Run migrations
alembic upgrade head

# Check current version
alembic current

# View migration history
alembic history
```

---

## Common Commands

### Check Migration Status
```bash
cd apps/sitefit/migrations
export DATABASE_URL="..."
alembic current
```

### Create New Migration
```bash
alembic revision -m "add new column to job table"
```

### Rollback Migration
```bash
alembic downgrade -1  # Go back one migration
```

### View History
```bash
alembic history --verbose
```

---

## Troubleshooting

### Can't connect to database

**Check**:
- Connection string is correct
- Password doesn't have special characters (or is properly escaped)
- Network access allowed (Supabase allows all IPs by default)

**Test connection**:
```bash
psql "postgresql://postgres.xxxxx:...@...pooler.supabase.com:6543/postgres"
```

### Migration fails

**Check**:
```bash
# View detailed error
cd apps/sitefit/migrations
export DATABASE_URL="..."
alembic upgrade head --verbose
```

**Common issues**:
- Missing `psycopg2-binary`: `pip install psycopg2-binary`
- Permission denied: Using service key instead of postgres connection string
- Extension error: Supabase should have `uuid-ossp` - check in SQL Editor

### Tables not appearing in Supabase

**Verify**:
```bash
# Check alembic_version table
psql "..." -c "SELECT * FROM alembic_version;"

# Should show: version_num = '001'
```

If no version, migration didn't run:
```bash
cd apps/sitefit/migrations
alembic upgrade head
```

---

## Next Steps

After setup complete:

1. **Update API code** - Add Service Bus + DB integration
2. **Update Worker code** - Add queue consumer + job processor
3. **Build images** - Tag with git SHA
4. **Push to ACR** - `docker push ...`
5. **Update Terragrunt** - New image tags
6. **Redeploy** - `terragrunt apply`
7. **Test** - End-to-end job flow

See `STAGE3_GUIDE.md` for detailed code updates.

---

## Database Schema

### `job` table
- Tracks job status (queued → running → succeeded/failed)
- Stores inputs with defaults materialized
- Hash for idempotency

### `result` table
- Stores computation outputs
- References job by ID
- Includes optional score

### `artifact` table
- Blob artifact URLs
- Expiration timestamps
- References job by ID

### `job_with_result` view
- Convenience view joining jobs and results
- Used by API status/result endpoints

---

## Production Deployment

When deploying to production:

```bash
# 1. Create production Supabase project

# 2. Get production connection string

# 3. Store in Key Vault
az keyvault secret set \
  --vault-name kuduso-prod-kv \
  --name DATABASE-URL \
  --value "postgresql://..."

# 4. Run migrations on prod database
export DATABASE_URL="postgresql://..."
cd apps/sitefit/migrations
alembic upgrade head

# 5. Verify tables created
# (Check Supabase Table Editor)

# 6. Deploy apps with prod Key Vault refs
```

---

## Resources

- **Alembic docs**: https://alembic.sqlalchemy.org
- **Supabase docs**: https://supabase.com/docs
- **Migration README**: `apps/sitefit/migrations/README.md`
- **Full guide**: `STAGE3_GUIDE.md`
