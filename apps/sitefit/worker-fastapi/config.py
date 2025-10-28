"""Configuration from environment variables"""
import os

# Database
DATABASE_URL = os.getenv("DATABASE_URL", "")

# Service Bus
SERVICEBUS_CONN = os.getenv("SERVICEBUS_CONN", "")
SERVICEBUS_QUEUE = os.getenv("SERVICEBUS_QUEUE", "sitefit-queue")

# AppServer
APP_SERVER_URL = os.getenv("APP_SERVER_URL", "http://kuduso-dev-appserver:8080/gh/{definition}:{version}/solve")

# Worker settings
LOCK_RENEW_SEC = int(os.getenv("LOCK_RENEW_SEC", "45"))
JOB_TIMEOUT_SEC = int(os.getenv("JOB_TIMEOUT_SEC", "240"))
MAX_ATTEMPTS = int(os.getenv("MAX_ATTEMPTS", "5"))
 