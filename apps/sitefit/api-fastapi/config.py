"""Configuration from environment variables"""
import os

# Database
DATABASE_URL = os.getenv("DATABASE_URL", "")

# Service Bus
SERVICEBUS_CONN = os.getenv("SERVICEBUS_CONNECTION_STRING", os.getenv("SERVICEBUS_CONN", ""))
SERVICEBUS_QUEUE = os.getenv("QUEUE_NAME", os.getenv("SERVICEBUS_QUEUE", "sitefit-queue"))

# AppServer (for fallback/testing)
APP_SERVER_URL = os.getenv("APPSERVER_URL", os.getenv("APP_SERVER_URL", "http://kuduso-dev-appserver:8080/gh/{definition}:{version}/solve"))

# Storage (for blob SAS)
BLOB_ACCOUNT = os.getenv("BLOB_ACCOUNT", "")
BLOB_SAS_SIGNING_KEY = os.getenv("BLOB_SAS_SIGNING", "")

# General
RESULT_CACHE_TTL = int(os.getenv("RESULT_CACHE_TTL", "300"))
