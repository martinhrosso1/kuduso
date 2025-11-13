#!/bin/bash
# Test script for AppServer - tests both mock and compute modes
# Usage: ./test-appserver.sh [mock|compute]

set -e

MODE="${1:-mock}"
APPSERVER_URL="${APPSERVER_URL:-http://localhost:8080}"
CORRELATION_ID="test-$(date +%s)"

echo "🧪 Testing AppServer in $MODE mode"
echo "URL: $APPSERVER_URL"
echo "Correlation ID: $CORRELATION_ID"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test 1: Health check
echo -e "${YELLOW}Test 1: Health check${NC}"
HEALTH=$(curl -s "$APPSERVER_URL/health")
echo "$HEALTH" | jq .
if echo "$HEALTH" | jq -e '.status == "ok"' > /dev/null; then
  echo -e "${GREEN}✓ Health check passed${NC}"
else
  echo -e "${RED}✗ Health check failed${NC}"
  exit 1
fi
echo ""

# Test 2: Readiness check
echo -e "${YELLOW}Test 2: Readiness check${NC}"
READY=$(curl -s "$APPSERVER_URL/ready")
echo "$READY" | jq .
if echo "$READY" | jq -e '.status == "ready"' > /dev/null; then
  echo -e "${GREEN}✓ Readiness check passed${NC}"
else
  echo -e "${RED}✗ Readiness check failed${NC}"
  exit 1
fi
echo ""

# Test 3: Minimal valid request
echo -e "${YELLOW}Test 3: Minimal valid request (golden test)${NC}"

PAYLOAD=$(cat <<EOF
{
  "crs": "EPSG:3857",
  "parcel": {
    "coordinates": [
      [0, 0],
      [10, 0],
      [10, 8],
      [0, 8],
      [0, 0]
    ]
  },
  "house": {
    "coordinates": [
      [0, 0],
      [4, 0],
      [4, 3],
      [0, 3],
      [0, 0]
    ]
  },
  "rotation": {
    "min": 0,
    "max": 90,
    "step": 45
  },
  "grid_step": 1.0,
  "seed": 42
}
EOF
)

RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST "$APPSERVER_URL/gh/sitefit:1.0.0/solve" \
  -H "Content-Type: application/json" \
  -H "x-correlation-id: $CORRELATION_ID" \
  -d "$PAYLOAD")

HTTP_BODY=$(echo "$RESPONSE" | sed -n '1,/HTTP_STATUS:/p' | sed '$d')
HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)

echo "HTTP Status: $HTTP_STATUS"
echo "$HTTP_BODY" | jq .

if [ "$HTTP_STATUS" = "200" ]; then
  echo -e "${GREEN}✓ Request succeeded${NC}"
  
  # Validate response structure
  RESULTS_COUNT=$(echo "$HTTP_BODY" | jq '.results | length')
  echo "Results count: $RESULTS_COUNT"
  
  if [ "$RESULTS_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Response has results${NC}"
    
    # Show first result details
    echo ""
    echo "First result:"
    echo "$HTTP_BODY" | jq '.results[0]'
  else
    echo -e "${YELLOW}⚠ No results returned${NC}"
  fi
else
  echo -e "${RED}✗ Request failed with status $HTTP_STATUS${NC}"
  exit 1
fi
echo ""

# Test 4: Invalid input (missing required field)
echo -e "${YELLOW}Test 4: Invalid input (should return 400)${NC}"

INVALID_PAYLOAD=$(cat <<EOF
{
  "parcel": {
    "coordinates": [[0,0], [10,0], [10,10], [0,10], [0,0]]
  }
}
EOF
)

INVALID_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST "$APPSERVER_URL/gh/sitefit:1.0.0/solve" \
  -H "Content-Type: application/json" \
  -H "x-correlation-id: $CORRELATION_ID-invalid" \
  -d "$INVALID_PAYLOAD")

INVALID_HTTP_BODY=$(echo "$INVALID_RESPONSE" | sed -n '1,/HTTP_STATUS:/p' | sed '$d')
INVALID_HTTP_STATUS=$(echo "$INVALID_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)

echo "HTTP Status: $INVALID_HTTP_STATUS"
echo "$INVALID_HTTP_BODY" | jq .

if [ "$INVALID_HTTP_STATUS" = "400" ]; then
  echo -e "${GREEN}✓ Correctly rejected invalid input${NC}"
else
  echo -e "${RED}✗ Expected 400, got $INVALID_HTTP_STATUS${NC}"
  exit 1
fi
echo ""

# Test 5: Non-existent definition
echo -e "${YELLOW}Test 5: Non-existent definition (should return 404)${NC}"

NOT_FOUND_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST "$APPSERVER_URL/gh/nonexistent:1.0.0/solve" \
  -H "Content-Type: application/json" \
  -H "x-correlation-id: $CORRELATION_ID-notfound" \
  -d "$PAYLOAD")

NOT_FOUND_HTTP_STATUS=$(echo "$NOT_FOUND_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)

echo "HTTP Status: $NOT_FOUND_HTTP_STATUS"

if [ "$NOT_FOUND_HTTP_STATUS" = "404" ]; then
  echo -e "${GREEN}✓ Correctly returned 404 for non-existent definition${NC}"
else
  echo -e "${RED}✗ Expected 404, got $NOT_FOUND_HTTP_STATUS${NC}"
  exit 1
fi
echo ""

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ All tests passed in $MODE mode${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

