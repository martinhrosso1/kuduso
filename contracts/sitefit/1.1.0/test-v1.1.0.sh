#!/bin/bash
# Quick test script for SiteFit v1.1.0 debug version

set -e

API_URL="https://kuduso-dev-sitefit-api.blackwave-77d88b66.westeurope.azurecontainerapps.io"

echo "🧪 Testing SiteFit v1.1.0 (Debug Version)"
echo "=========================================="
echo ""

# Test 1: Minimal valid input
echo "📝 Test 1: Minimal input (value=42, expected result=52)"
JOB_RESPONSE=$(curl -s -X POST "$API_URL/jobs/run" \
  -H "Content-Type: application/json" \
  -d '{
    "app_id": "sitefit",
    "definition": "sitefit",
    "version": "1.1.0",
    "inputs": {"value": 42}
  }')

echo "$JOB_RESPONSE" | python3 -m json.tool
JOB_ID=$(echo "$JOB_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('job_id', ''))" 2>/dev/null || echo "")

if [ -z "$JOB_ID" ]; then
  echo "❌ Failed to submit job"
  exit 1
fi

echo ""
echo "📝 Job ID: $JOB_ID"
echo ""
echo "⏳ Waiting 10 seconds..."
sleep 10

echo ""
echo "📊 Checking status..."
STATUS=$(curl -s "$API_URL/jobs/status/$JOB_ID")
echo "$STATUS" | python3 -m json.tool

JOB_STATUS=$(echo "$STATUS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('status', ''))" 2>/dev/null || echo "")

if [ "$JOB_STATUS" = "succeeded" ]; then
  echo ""
  echo "✅ SUCCESS! Getting result..."
  RESULT=$(curl -s "$API_URL/jobs/result/$JOB_ID")
  echo "$RESULT" | python3 -m json.tool
  
  RESULT_VALUE=$(echo "$RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('result', ''))" 2>/dev/null || echo "")
  
  if [ "$RESULT_VALUE" = "52" ]; then
    echo ""
    echo "🎉 PERFECT! Result is 52 (42 + 10)"
    echo "✅ Infrastructure is working correctly!"
  else
    echo ""
    echo "⚠️  Got result: $RESULT_VALUE (expected 52)"
  fi
elif [ "$JOB_STATUS" = "running" ]; then
  echo ""
  echo "⏳ Still running, wait a bit more..."
elif [ "$JOB_STATUS" = "failed" ]; then
  echo ""
  echo "❌ Job failed. Check logs:"
  echo "   az containerapp logs show --name kuduso-dev-appserver --resource-group kuduso-dev-rg --tail 50"
else
  echo ""
  echo "⚠️  Unexpected status: $JOB_STATUS"
fi

