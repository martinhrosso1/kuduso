"""Database operations for worker"""
import psycopg2
import psycopg2.extras
import psycopg2.extensions
import json
from typing import Optional, Dict, Any
from datetime import datetime
import uuid
import logging

from config import DATABASE_URL

logger = logging.getLogger(__name__)

# Register UUID adapter for psycopg2
psycopg2.extras.register_uuid()


class Database:
    """Database connection manager for worker"""
    
    def __init__(self):
        self.conn_string = DATABASE_URL
        
    def get_connection(self):
        """Get database connection"""
        return psycopg2.connect(self.conn_string)
    
    def update_job_status(
        self,
        job_id: str,
        status: str,
        started_at: Optional[datetime] = None,
        ended_at: Optional[datetime] = None,
        increment_attempts: bool = False
    ) -> None:
        """Update job status"""
        try:
            with self.get_connection() as conn:
                with conn.cursor() as cur:
                    if increment_attempts:
                        cur.execute("""
                            UPDATE job
                            SET status = %s,
                                started_at = COALESCE(%s, started_at),
                                ended_at = %s,
                                attempts = attempts + 1
                            WHERE id = %s
                        """, (status, started_at, ended_at, uuid.UUID(job_id)))
                    else:
                        cur.execute("""
                            UPDATE job
                            SET status = %s,
                                started_at = COALESCE(%s, started_at),
                                ended_at = %s
                            WHERE id = %s
                        """, (status, started_at, ended_at, uuid.UUID(job_id)))
                conn.commit()
                
            logger.info(f"Job {job_id} status updated to {status}")
            
        except Exception as e:
            logger.error(f"Failed to update job {job_id} status: {e}")
            raise
    
    def update_job_error(self, job_id: str, error: Dict[str, Any]) -> None:
        """Update job error information"""
        try:
            with self.get_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        UPDATE job
                        SET last_error = %s,
                            status = 'failed',
                            ended_at = now()
                        WHERE id = %s
                    """, (json.dumps(error), uuid.UUID(job_id)))
                conn.commit()
                
            logger.info(f"Job {job_id} error updated")
            
        except Exception as e:
            logger.error(f"Failed to update job {job_id} error: {e}")
            raise
    
    def insert_result(
        self,
        job_id: str,
        outputs_json: Dict[str, Any],
        score: Optional[float] = None
    ) -> None:
        """Insert job result"""
        try:
            with self.get_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        INSERT INTO result (job_id, outputs_json, score)
                        VALUES (%s, %s, %s)
                    """, (uuid.UUID(job_id), json.dumps(outputs_json), score))
                conn.commit()
                
            logger.info(f"Result inserted for job {job_id}")
            
        except Exception as e:
            logger.error(f"Failed to insert result for job {job_id}: {e}")
            raise
    
    def get_job_attempts(self, job_id: str) -> int:
        """Get current attempt count for a job"""
        try:
            with self.get_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        SELECT attempts FROM job WHERE id = %s
                    """, (uuid.UUID(job_id),))
                    row = cur.fetchone()
                    return row[0] if row else 0
        except Exception as e:
            logger.error(f"Failed to get attempts for job {job_id}: {e}")
            return 0


# Global database instance
db = Database()
