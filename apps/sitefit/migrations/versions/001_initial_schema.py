"""Initial schema for job queue and results

Revision ID: 001
Revises: 
Create Date: 2025-10-27 14:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '001'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create initial schema for job tracking and results."""
    
    # Enable UUID extension
    op.execute('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"')
    
    # Create job table
    op.create_table(
        'job',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('tenant_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('app_id', sa.Text(), nullable=False),
        sa.Column('definition', sa.Text(), nullable=False),
        sa.Column('version', sa.Text(), nullable=False),
        sa.Column('status', sa.Text(), nullable=False),
        sa.Column('inputs_hash', sa.Text(), nullable=False),
        sa.Column('payload_json', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column('attempts', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('priority', sa.Integer(), nullable=False, server_default='100'),
        sa.Column('last_error', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text('now()')),
        sa.Column('started_at', sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column('ended_at', sa.TIMESTAMP(timezone=True), nullable=True),
        sa.CheckConstraint("status IN ('queued', 'running', 'succeeded', 'failed')", name='job_status_check'),
    )
    
    # Create indexes for job table
    op.create_index('job_status_idx', 'job', ['status', 'created_at'])
    op.create_index('job_inputs_hash_idx', 'job', ['inputs_hash'])
    op.create_index('job_tenant_idx', 'job', ['tenant_id', 'created_at'])
    op.create_index('job_app_def_ver_idx', 'job', ['app_id', 'definition', 'version'])
    
    # Create result table
    op.create_table(
        'result',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('job_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('outputs_json', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column('score', sa.Numeric(), nullable=True),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text('now()')),
        sa.ForeignKeyConstraint(['job_id'], ['job.id'], ondelete='CASCADE'),
    )
    
    # Create index for result table
    op.create_index('result_job_id_idx', 'result', ['job_id'])
    
    # Create artifact table
    op.create_table(
        'artifact',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('job_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('kind', sa.Text(), nullable=False),
        sa.Column('url', sa.Text(), nullable=False),
        sa.Column('expires_at', sa.TIMESTAMP(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['job_id'], ['job.id'], ondelete='CASCADE'),
    )
    
    # Create indexes for artifact table
    op.create_index('artifact_job_id_idx', 'artifact', ['job_id'])
    op.create_index('artifact_expires_idx', 'artifact', ['expires_at'], postgresql_where=sa.text('expires_at IS NOT NULL'))
    
    # Enable RLS (Row Level Security) - tables will be accessible via policies
    op.execute('ALTER TABLE job ENABLE ROW LEVEL SECURITY')
    op.execute('ALTER TABLE result ENABLE ROW LEVEL SECURITY')
    op.execute('ALTER TABLE artifact ENABLE ROW LEVEL SECURITY')
    
    # Create policies for authenticated users (development)
    # These are permissive for now - tighten in production
    op.execute("""
        CREATE POLICY "Enable all for authenticated users" ON job
        FOR ALL USING (auth.role() = 'authenticated')
    """)
    
    op.execute("""
        CREATE POLICY "Enable all for authenticated users" ON result
        FOR ALL USING (auth.role() = 'authenticated')
    """)
    
    op.execute("""
        CREATE POLICY "Enable all for authenticated users" ON artifact
        FOR ALL USING (auth.role() = 'authenticated')
    """)
    
    # Create policies for service role (API/Worker with service key)
    op.execute("""
        CREATE POLICY "Enable all for service role" ON job
        FOR ALL USING (auth.role() = 'service_role')
    """)
    
    op.execute("""
        CREATE POLICY "Enable all for service role" ON result
        FOR ALL USING (auth.role() = 'service_role')
    """)
    
    op.execute("""
        CREATE POLICY "Enable all for service role" ON artifact
        FOR ALL USING (auth.role() = 'service_role')
    """)
    
    # Create helper view: job with result
    op.execute("""
        CREATE OR REPLACE VIEW job_with_result AS
        SELECT 
            j.*,
            r.outputs_json,
            r.score,
            r.created_at as result_created_at
        FROM job j
        LEFT JOIN result r ON r.job_id = j.id
    """)
    
    # Grant access to service role
    op.execute('GRANT ALL ON job TO service_role')
    op.execute('GRANT ALL ON result TO service_role')
    op.execute('GRANT ALL ON artifact TO service_role')
    op.execute('GRANT ALL ON job_with_result TO service_role')
    
    # Add comments for documentation
    op.execute("COMMENT ON TABLE job IS 'Job queue and status tracking'")
    op.execute("COMMENT ON TABLE result IS 'Job computation results'")
    op.execute("COMMENT ON TABLE artifact IS 'Job output artifacts (blobs)'")
    op.execute("COMMENT ON COLUMN job.inputs_hash IS 'SHA-256 hash for idempotency and caching'")
    op.execute("COMMENT ON COLUMN job.payload_json IS 'Inputs with defaults materialized'")
    op.execute("COMMENT ON COLUMN job.attempts IS 'Number of processing attempts'")
    op.execute("COMMENT ON COLUMN job.priority IS 'Job priority (higher = more important)'")


def downgrade() -> None:
    """Drop all tables and objects."""
    
    # Drop view
    op.execute('DROP VIEW IF EXISTS job_with_result')
    
    # Drop tables (CASCADE will drop dependent objects)
    op.drop_table('artifact')
    op.drop_table('result')
    op.drop_table('job')
    
    # Drop UUID extension
    op.execute('DROP EXTENSION IF EXISTS "uuid-ossp"')
