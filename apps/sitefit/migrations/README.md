# Database Migrations

This directory contains Alembic migrations for the sitefit application database.

## Setup

Install dependencies:

```bash
pip install alembic psycopg2-binary sqlalchemy
```

## Running Migrations

Set your database URL:

```bash
export DATABASE_URL="postgresql://postgres:password@host:port/database"
```

Run migrations:

```bash
# Upgrade to latest
alembic upgrade head

# Downgrade one revision
alembic downgrade -1

# Show current revision
alembic current

# Show migration history
alembic history --verbose
```

## Creating New Migrations

```bash
# Create a new migration
alembic revision -m "description of changes"

# Or use autogenerate (requires models)
alembic revision --autogenerate -m "description of changes"
```

## Directory Structure

```
migrations/
├── alembic.ini          # Alembic configuration
├── env.py               # Migration environment setup
├── script.py.mako       # Template for new migrations
└── versions/            # Migration scripts
    └── 001_initial_schema.py
```

## Migrations

### 001_initial_schema.py

Creates the initial database schema:

- **job** - Job queue and status tracking
- **result** - Job computation results  
- **artifact** - Job output artifacts (blob URLs)
- **job_with_result** - Convenience view joining jobs and results

Includes:
- UUID extension
- JSONB columns for flexible data
- Indexes for performance
- Row Level Security (RLS) policies
- Service role permissions

## Supabase-Specific Notes

This migration is designed for Supabase (PostgreSQL):

- Uses `auth.role()` for RLS policies
- Creates policies for `authenticated` and `service_role`
- Grants permissions to `service_role` for API/Worker access

When connecting from API/Worker, use the **service role key** (not anon key) to bypass RLS if needed, or implement proper tenant-based policies.

## Environment Variables

The migration uses the `DATABASE_URL` environment variable:

```bash
# Supabase connection (from Project Settings → Database)
export DATABASE_URL="postgresql://postgres.[project-ref]:[password]@aws-0-[region].pooler.supabase.com:6543/postgres"
```

## Troubleshooting

### Connection Issues

If you can't connect, verify:
- Database URL is correct
- Password doesn't contain special characters that need escaping
- Network access is allowed (Supabase allows all IPs by default)

### Permission Issues

If migrations fail with permission errors:
- Ensure you're using the connection string from Supabase (has superuser privileges)
- Check that `service_role` exists in your Supabase project

### Running in CI/CD

```bash
# In GitHub Actions, Azure Pipelines, etc.
export DATABASE_URL="${{ secrets.DATABASE_URL }}"
alembic upgrade head
```

## Rolling Back

To rollback a migration:

```bash
# Rollback one migration
alembic downgrade -1

# Rollback to specific revision
alembic downgrade <revision_id>

# Rollback all
alembic downgrade base
```

## Best Practices

1. **Always test migrations** on a dev database first
2. **Never edit applied migrations** - create a new one instead
3. **Use transactions** - migrations run in a transaction by default
4. **Keep migrations small** - easier to review and rollback
5. **Document breaking changes** in migration comments
6. **Backup before production migrations**

## Production Deployment

Before deploying to production:

```bash
# 1. Backup database
# (Supabase has automatic backups, but create a manual one)

# 2. Test migration on staging
export DATABASE_URL="<staging-url>"
alembic upgrade head

# 3. Verify application works

# 4. Deploy to production
export DATABASE_URL="<production-url>"
alembic upgrade head

# 5. Verify application works
```
