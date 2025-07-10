#!/bin/bash
set -e

# Input arguments
DOJO_URL=$1
DOJO_API_KEY=$2
PRODUCT_NAME=$3
SCAN_FILE=$4
ENGAGEMENT_NAME=$5        # Repo name
TEST_TITLE=$6             # Branch + Commit ID

# Validation
if [ -z "$DOJO_URL" ] || [ -z "$DOJO_API_KEY" ] || [ -z "$PRODUCT_NAME" ] || [ -z "$SCAN_FILE" ] || [ -z "$ENGAGEMENT_NAME" ] || [ -z "$TEST_TITLE" ]; then
  echo "Usage: $0 <DOJO_URL> <DOJO_API_KEY> <PRODUCT_NAME> <SCAN_FILE> <ENGAGEMENT_NAME> <TEST_TITLE>"
  exit 1
fi

if [ ! -f "$SCAN_FILE" ]; then
  echo "❌ Scan file $SCAN_FILE not found!"
  exit 1
fi

DATE=$(date +%F)
AUTH_HEADER="Authorization: Token $DOJO_API_KEY"
JSON_HEADER="Content-Type: application/json"

echo "📤 Uploading $SCAN_FILE to DefectDojo..."
echo "🔍 PRODUCT_NAME: '$PRODUCT_NAME'"
echo "🔍 ENGAGEMENT_NAME: '$ENGAGEMENT_NAME'"
echo "🔍 TEST_TITLE: '$TEST_TITLE'"

# Get Product ID by name (reliable way)
PRODUCT_ID=$(curl -s -H "$AUTH_HEADER" "$DOJO_URL/api/v2/products/" | \
  jq -r --arg name "$PRODUCT_NAME" '.results[] | select(.name == $name) | .id')

if [ -z "$PRODUCT_ID" ] || [ "$PRODUCT_ID" == "null" ]; then
  echo "❌ Product '$PRODUCT_NAME' not found in DefectDojo."
  echo "📋 Available products:"
  curl -s -H "$AUTH_HEADER" "$DOJO_URL/api/v2/products/" | jq -r '.results[].name'
  exit 1
fi

echo "✅ Found Product ID: $PRODUCT_ID"

# Check if engagement exists
ENGAGEMENT_ID=$(curl -s -H "$AUTH_HEADER" "$DOJO_URL/api/v2/engagements/?product=$PRODUCT_ID&name=$ENGAGEMENT_NAME" | jq -r '.results[0].id')

if [ -z "$ENGAGEMENT_ID" ] || [ "$ENGAGEMENT_ID" == "null" ]; then
  echo "➕ Creating new engagement: $ENGAGEMENT_NAME"
  ENGAGEMENT_ID=$(curl -s -X POST "$DOJO_URL/api/v2/engagements/" \
    -H "$AUTH_HEADER" -H "$JSON_HEADER" \
    -d "{
      \"product\": $PRODUCT_ID,
      \"name\": \"$ENGAGEMENT_NAME\",
      \"target_start\": \"$DATE\",
      \"target_end\": \"$DATE\",
      \"status\": \"In Progress\",
      \"engagement_type\": \"CI/CD\"
    }" | jq -r '.id')

  if [ -z "$ENGAGEMENT_ID" ] || [ "$ENGAGEMENT_ID" == "null" ]; then
    echo "❌ Failed to create engagement."
    exit 1
  fi
else
  echo "✅ Engagement '$ENGAGEMENT_NAME' already exists with ID $ENGAGEMENT_ID"
fi

# Upload the scan
echo "📤 Reimporting scan into engagement..."
curl -s -X POST "$DOJO_URL/api/v2/reimport-scan/" \
  -H "$AUTH_HEADER" \
  -F "scan_date=$DATE" \
  -F "scan_type=Gitleaks Scan" \
  -F "active=true" \
  -F "verified=true" \
  -F "product_name=$PRODUCT_NAME" \
  -F "engagement_name=$ENGAGEMENT_NAME" \
  -F "test_title=$TEST_TITLE - $DATE" \
  -F "auto_create_context=true" \
  -F "deduplication_on_engagement=true" \
  -F "close_old_findings=true" \
  -F "engagement_end_date=$(date -d '+365 days' +%F)" \
  -F "file=@$SCAN_FILE"

echo "✅ Upload complete!"
