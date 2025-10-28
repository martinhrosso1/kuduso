# ✅ Stage 3 - Alembic Migration Setup Complete

## 📦 What Was Created

### Migration Structure

```
apps/sitefit/migrations/
├── README.md                    # Complete migration documentation
├── requirements.txt             # Python dependencies
├── alembic.ini                  # Alembic configuration
├── env.py                       # Migration environment
├── script.py.mako              # Template for new migrations
└── versions/
    └── 001_initial_schema.py   # Initial database schema
```

### Setup Script

- **`STAGE3_SETUP.sh`** - Automated setup that:
  - Stores secrets in Key Vault
  - Installs Alembic dependencies
  - **Runs migrations automatically** ✨
  - Verifies setup

### Documentation

- **`STAGE3_QUICKSTART.md`** - Quick reference (updated for Alembic)
- **`STAGE3_GUIDE.md`** - Full implementation guide (updated for Alembic)
- **`apps/sitefit/migrations/README.md`** - Migration-specific docs

---

## 🎯 Database Schema (from Migration 001)

The initial migration creates:

### Tables

**`job`** - Job queue and status tracking
- id, tenant_id, app_id, definition, version
- status (queued/running/succeeded/failed)
- inputs_hash (SHA-256 for idempotency)
- payload_json (inputs with defaults)
- attempts, priority, last_error
- created_at, started_at, ended_at

**`result`** - Job computation results
- id, job_id (FK), outputs_json, score
- created_at

**`artifact`** - Blob artifact URLs
- id, job_id (FK), kind, url
- expires_at

### Indexes

- `job_status_idx` - Query by status + date
- `job_inputs_hash_idx` - Idempotency lookups
- `job_tenant_idx` - Tenant filtering
- `job_app_def_ver_idx` - App/definition queries
- `result_job_id_idx` - Result lookups
- `artifact_job_id_idx` - Artifact lookups
- `artifact_expires_idx` - Cleanup queries

### Views

**`job_with_result`** - Convenience view
- Joins job + result for API endpoints
- Used by `/jobs/status` and `/jobs/result`

### Security

- **Row Level Security (RLS)** enabled on all tables
- Policies for `authenticated` users
- Policies for `service_role` (API/Worker)
- Grants for service role access

---

## 🚀 How to Use

### One-Time Setup (10 minutes)

```bash
# 1. Create Supabase project
# (see STAGE3_QUICKSTART.md)

# 2. Get connection string
# (from Supabase Project Settings → Database)

# 3. Run setup script
cd /home/martin/Desktop/kuduso
chmod +x STAGE3_SETUP.sh
./STAGE3_SETUP.sh
```

**Done!** Script handles everything:
- Stores `DATABASE-URL` in Key Vault
- Installs Alembic
- Runs `alembic upgrade head`
- Creates all tables/indexes/views
- Stores other secrets

### Verify Setup

**In Supabase** → Table Editor:
- ✅ `job`
- ✅ `result`
- ✅ `artifact`
- ✅ `alembic_version` (shows: 001)

**In Azure** → Key Vault:
```bash
az keyvault secret list --vault-name kuduso-dev-kv-93d2ab --query "[].name"
```

Should show:
- DATABASE-URL
- SERVICEBUS-CONN
- BLOB-SAS-SIGNING
- COMPUTE-API-KEY (from Stage 2)

---

## 🔧 Managing Migrations

### Check Current Version

```bash
cd apps/sitefit/migrations
export DATABASE_URL="postgresql://..."
alembic current
```

Output: `001 (head)`

### View History

```bash
alembic history --verbose
```

### Create New Migration

```bash
# Describe what you're changing
alembic revision -m "add job timeout column"

# Edit the generated file in versions/
# Then run:
alembic upgrade head
```

### Rollback

```bash
# Rollback one migration
alembic downgrade -1

# Rollback to specific version
alembic downgrade 001

# Rollback all (nuclear option)
alembic downgrade base
```

---

## 📝 Migration File Example

The generated `001_initial_schema.py`:

```python
def upgrade() -> None:
    """Create initial schema."""
    # Create tables
    op.create_table('job', ...)
    op.create_table('result', ...)
    op.create_table('artifact', ...)
    
    # Create indexes
    op.create_index('job_status_idx', ...)
    
    # Enable RLS
    op.execute('ALTER TABLE job ENABLE ROW LEVEL SECURITY')
    
    # Create policies
    op.execute('CREATE POLICY ...')

def downgrade() -> None:
    """Drop all tables."""
    op.drop_table('artifact')
    op.drop_table('result')
    op.drop_table('job')
```

Clean, version-controlled, and repeatable! ✅

---

## 🎯 Advantages of Alembic

vs. Manual SQL:

| Feature | Alembic | Manual SQL |
|---------|---------|------------|
| Version control | ✅ Git tracked | ❌ Copy/paste |
| Rollback | ✅ `downgrade` | ❌ Manual restore |
| Repeatable | ✅ Run anywhere | ❌ One-time |
| History | ✅ `alembic history` | ❌ Document manually |
| CI/CD friendly | ✅ `upgrade head` | ❌ Manual steps |
| Team collaboration | ✅ Merge migrations | ❌ Conflicts |

---

## 🔐 Production Checklist

Before running migrations in production:

- [ ] Test migration on staging database first
- [ ] Backup production database
- [ ] Review migration SQL (Alembic shows you)
- [ ] Run during low-traffic window
- [ ] Have rollback plan ready
- [ ] Monitor application logs after
- [ ] Verify data integrity

### Production Command

```bash
# Set production DATABASE_URL
export DATABASE_URL="postgresql://postgres.prod:...@..."

# Run migration
cd apps/sitefit/migrations
alembic upgrade head

# Verify
alembic current
psql "$DATABASE_URL" -c "SELECT count(*) FROM job;"
```

---

## 🐛 Troubleshooting

### "No module named alembic"

```bash
pip install -r apps/sitefit/migrations/requirements.txt
```

### "Can't locate revision identified by '001'"

Migration files not found. Check:
```bash
ls apps/sitefit/migrations/versions/
# Should show: 001_initial_schema.py
```

### "Could not connect to database"

Check DATABASE_URL:
```bash
echo $DATABASE_URL
# Should start with: postgresql://...
```

Test connection:
```bash
psql "$DATABASE_URL" -c "SELECT 1;"
```

### "Permission denied for table"

Using wrong role. Should use:
- **Supabase**: postgres connection string (from Project Settings)
- **Not**: service_role key or anon key

---

## 📚 Resources

### Documentation
- `apps/sitefit/migrations/README.md` - Detailed migration guide
- `STAGE3_QUICKSTART.md` - Quick setup reference
- `STAGE3_GUIDE.md` - Full Stage 3 guide

### External Docs
- [Alembic Tutorial](https://alembic.sqlalchemy.org/en/latest/tutorial.html)
- [Supabase Database](https://supabase.com/docs/guides/database)
- [PostgreSQL Docs](https://www.postgresql.org/docs/)

---

## ✅ Next Steps

Database is ready! Now:

1. **Update API code** - Integrate Supabase + Service Bus
2. **Update Worker code** - Queue consumer + job processor
3. **Build images** - New code → new images
4. **Deploy** - Push to ACR → Redeploy apps
5. **Test** - End-to-end flow

See `STAGE3_GUIDE.md` for code updates.

---

## 🎉 Summary

You now have:

✅ **Professional database migrations** with Alembic  
✅ **Version-controlled schema** in Git  
✅ **Automated setup script** for new environments  
✅ **Repeatable deployments** (dev, staging, prod)  
✅ **Rollback capability** if needed  
✅ **Complete documentation** for team  

**Much better than manual SQL! 🚀**
