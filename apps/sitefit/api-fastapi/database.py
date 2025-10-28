"""Database operations using psycopg2"""
import psycopg2
import psycopg2.extras
import json
from typing import Optional, Dict, Any
from datetime import datetime
import uuid
import logging

from config import DATABASE_URL

logger = logging.getLogger(__name__)


class Database:
    """Database connection manager"""
    
    def __init__(self):
        self.conn_string = DATABASE_URL
        
    def get_connection(self):
        """Get database connection"""
        return psycopg2.connect(self.conn_string)
    
    def insert_job(
        self,
        job_id: str,
        tenant_id: Optional[str],
        app_id: str,
        definition: str,
        version: str,
        inputs_hash: str,
        payload_json: Dict[str, Any]
    ) -> None:
        """Insert a new job into the database"""
        try:
            with self.get_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        INSERT INTO job (
                            id, tenant_id, app_id, definition, version,
                            status, inputs_hash, payload_json, attempts, priority
                        ) VALUES (
                            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
                        )
                    """, (
                        uuid.UUID(job_id),
                        uuid.UUID(tenant_id) if tenant_id else None,
                        app_id,
                        definition,
                        version,
                        'queued',
                        inputs_hash,
                        json.dumps(payload_json),
                        0,
                        100
                    ))
                conn.commit()
                
            logger.info(f"Job {job_id} inserted into database")
            
        except Exception as e:
            logger.error(f"Failed to insert job {job_id}: {e}")
            raise
    
    def get_job(self, job_id: str) -> Optional[Dict[str, Any]]:
        """Get job by ID"""
        try:
            with self.get_connection() as conn:
                with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                    cur.execute("""
                        SELECT 
                            j.id::text as job_id,
                            j.tenant_id::text,
                            j.app_id,
                            j.definition,
                            j.version,
                            j.status,
                            j.inputs_hash,
                            j.payload_json,
                            j.attempts,
                            j.priority,
                            j.last_error,
                            j.created_at,
                            j.started_at,
                            j.ended_at,
                            r.outputs_json,
                            r.score
                        FROM job j
                        LEFT JOIN result r ON r.job_id = j.id
                        WHERE j.id = %s
                    """, (uuid.UUID(job_id),))
                    
                    row = cur.fetchone()
                    if row:
                        return dict(row)
                    return None
                    
        except Exception as e:
            logger.error(f"Failed to get job {job_id}: {e}")
            raise
    
    def get_job_status(self, job_id: str) -> Optional[Dict[str, Any]]:
        """Get job status"""
        try:
            with self.get_connection() as conn:
                with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                    cur.execute("""
                        SELECT 
                            id::text as job_id,
                            status,
                            attempts,
                            last_error,
                            created_at,
                            started_at,
                            ended_at
                        FROM job
                        WHERE id = %s
                    """, (uuid.UUID(job_id),))
                    
                    row = cur.fetchone()
                    if row:
                        return dict(row)
                    return None
                    
        except Exception as e:
            logger.error(f"Failed to get job status {job_id}: {e}")
            raise
    
    def get_job_result(self, job_id: str) -> Optional[Dict[str, Any]]:
        """Get job result"""
        try:
            with self.get_connection() as conn:
                with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                    cur.execute("""
                        SELECT 
                            j.id::text as job_id,
                            j.status,
                            r.outputs_json,
                            r.score,
                            r.created_at as result_created_at
                        FROM job j
                        LEFT JOIN result r ON r.job_id = j.id
                        WHERE j.id = %s
                    """, (uuid.UUID(job_id),))
                    
                    row = cur.fetchone()
                    if row:
                        return dict(row)
                    return None
                    
        except Exception as e:
            logger.error(f"Failed to get job result {job_id}: {e}")
            raise
    
    def check_duplicate_by_hash(self, inputs_hash: str) -> Optional[Dict[str, Any]]:
        """Check if a job with this inputs_hash already exists"""
        try:
            with self.get_connection() as conn:
                with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                    cur.execute("""
                        SELECT 
                            id::text as job_id,
                            status,
                            created_at
                        FROM job
                        WHERE inputs_hash = %s
                        AND status IN ('queued', 'running', 'succeeded')
                        ORDER BY created_at DESC
                        LIMIT 1
                    """, (inputs_hash,))
                    
                    row = cur.fetchone()
                    if row:
                        return dict(row)
                    return None
                    
        except Exception as e:
            logger.error(f"Failed to check duplicate hash {inputs_hash}: {e}")
            raise


# Global database instance
db = Database()
