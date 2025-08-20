#!/bin/bash
set -e

# -------------------------
# Script to upload Gitleaks scan results to DefectDojo
# - Engagement = Repository
# - Test       = Branch inside Engagement
#
# Rules:
# 1. If no secrets and no engagement/test exist yet → do nothing.
# 2. If secrets found for the first time → create engagement + test.
# 3. If secrets found later in same branch → reimport into existing test.
# 4. If secrets found in a new branch → create new test in existing engagement.
# 5. If no secrets but engagement/test already exist → reimport empty scan to close findings.
# -------------------------

DOJO_URL=$1
DOJO_API_KEY=$2
PRODUCT_NAME=$3
SCAN_FILE=$4
REPO_NAME=$5       # Engagement name
BRANCH_NAME=$6     # Test title inside engagement

if [ -z "$DOJO_URL" ] || [ -z "$DOJO_API_KEY" ] || [ -z "$PRODUCT_NAME" ] || [ -z "$SCAN_FILE" ] || [ -z "$REPO_NAME" ] || [ -z "$BRANCH_NAME" ]; then
  echo "Usage: $0 <DOJO_URL> <DOJO_API_KEY> <PRODUCT_NAME> <SCAN_FILE> <REPO_NAME> <BRANCH_NAME>"
  exit 1
fi

if [ ! -f "$SCAN_FILE" ]; then
  echo "❌ Scan file $SCAN_FILE not found!"
  exit 1
fi

DATE=$(date +%F)
END_DATE=$(date -d '+7300 days' +%F)  # 20 years later for engagement
AUTH_HEADER="Authorization: Token $DOJO_API_KEY"
JSON_HEADER="Content-Type: application/json"

# -------------------------
# Step 1: Check if secrets are present in scan
# -------------------------
SECRETS_FOUND=$(jq '.[] | select(.Rule != null)' "$SCAN_FILE" | wc -l)

# -------------------------
# Step 2: Find Product ID in DefectDojo
# -------------------------
PRODUCT_ID=$(curl -s -H "$AUTH_HEADER" "$DOJO_URL/api/v2/products/?limit=1000" | \
  jq -r --arg name "$PRODUCT_NAME" '.results[] | select(.name == $name) | .id')

if [ -z "$PRODUCT_ID" ] || [ "$PRODUCT_ID" == "null" ]; then
  echo "❌ Product '$PRODUCT_NAME' not found in DefectDojo."
  exit 1
fi

# -------------------------
# Step 3: Check or create Engagement (repo)
# -------------------------
ENGAGEMENT_NAME="$REPO_NAME"
ENGAGEMENT_ID=$(curl -s -H "$AUTH_HEADER" \
  "$DOJO_URL/api/v2/engagements/?product=$PRODUCT_ID&name=$ENGAGEMENT_NAME" \
  | jq -r '.results[0].id')

if [ -z "$ENGAGEMENT_ID" ] || [ "$ENGAGEMENT_ID" == "null" ]; then
  if [ "$SECRETS_FOUND" -eq 0 ]; then
    echo "✅ No findings found. Engagement/test do not exist → skipping upload."
    exit 0
  fi
  echo "📁 Creating engagement '$ENGAGEMENT_NAME'..."
  ENGAGEMENT_ID=$(curl -s -X POST "$DOJO_URL/api/v2/engagements/" \
    -H "$AUTH_HEADER" -H "$JSON_HEADER" \
    -d "{
      \"product\": $PRODUCT_ID,
      \"name\": \"$ENGAGEMENT_NAME\",
      \"target_start\": \"$DATE\",
      \"target_end\": \"$END_DATE\",
      \"status\": \"In Progress\",
      \"engagement_type\": \"CI/CD\"
    }" | jq -r '.id')
fi

# -------------------------
# Step 4: Check or create Test (branch)
# -------------------------
TEST_TITLE="$BRANCH_NAME"
TEST_ID=$(curl -s -H "$AUTH_HEADER" \
  "$DOJO_URL/api/v2/tests/?engagement=$ENGAGEMENT_ID&title=$TEST_TITLE" \
  | jq -r '.results[0].id')

if [ -z "$TEST_ID" ] || [ "$TEST_ID" == "null" ]; then
  if [ "$SECRETS_FOUND" -eq 0 ]; then
    echo "✅ No findings found. Test for branch '$TEST_TITLE' does not exist → skipping upload."
    exit 0
  fi
  echo "🧪 Creating test '$TEST_TITLE' in engagement '$ENGAGEMENT_NAME'..."
  # Test will actually be created implicitly by first reimport-scan call
else
  if [ "$SECRETS_FOUND" -eq 0 ]; then
    echo "✅ No findings found. Updating existing test '$TEST_TITLE' to close old findings."
  fi
fi

# -------------------------
# Step 5: Upload or reimport scan
# -------------------------
curl -s -X POST "$DOJO_URL/api/v2/reimport-scan/" \
  -H "$AUTH_HEADER" \
  -F "scan_date=$DATE" \
  -F "scan_type=Gitleaks Scan" \
  -F "active=true" \
  -F "verified=true" \
  -F "product_name=$PRODUCT_NAME" \
  -F "engagement_name=$ENGAGEMENT_NAME" \
  -F "test_title=$TEST_TITLE" \
  -F "auto_create_context=true" \
  -F "deduplication_on_engagement=true" \
  -F "close_old_findings=true" \
  -F "engagement_end_date=$(date -d '+365 days' +%F)" \
  -F "file=@$SCAN_FILE"

echo "✅ Scan uploaded to engagement '$ENGAGEMENT_NAME' with test '$TEST_TITLE'"


# #!/bin/bash
# set -e

# DOJO_URL=$1
# DOJO_API_KEY=$2
# PRODUCT_NAME=$3
# SCAN_FILE=$4
# REPO_NAME=$5
# BRANCH_NAME=$6

# if [ -z "$DOJO_URL" ] || [ -z "$DOJO_API_KEY" ] || [ -z "$PRODUCT_NAME" ] || [ -z "$SCAN_FILE" ] || [ -z "$REPO_NAME" ] || [ -z "$BRANCH_NAME" ]; then
#   echo "Usage: $0 <DOJO_URL> <DOJO_API_KEY> <PRODUCT_NAME> <SCAN_FILE> <REPO_NAME> <BRANCH_NAME>"
#   exit 1
# fi

# if [ ! -f "$SCAN_FILE" ]; then
#   echo "❌ Scan file $SCAN_FILE not found!"
#   exit 1
# fi

# DATE=$(date +%F)
# END_DATE=$(date -d '+7300 days' +%F)  # 20 years later
# AUTH_HEADER="Authorization: Token $DOJO_API_KEY"
# JSON_HEADER="Content-Type: application/json"

# # Get Product ID
# PRODUCT_ID=$(curl -s -H "$AUTH_HEADER" "$DOJO_URL/api/v2/products/?limit=1000" | \
#   jq -r --arg name "$PRODUCT_NAME" '.results[] | select(.name == $name) | .id')

# if [ -z "$PRODUCT_ID" ] || [ "$PRODUCT_ID" == "null" ]; then
#   echo "❌ Product '$PRODUCT_NAME' not found."
#   exit 1
# fi

# # Engagement = one per repo name
# ENGAGEMENT_NAME="$REPO_NAME"

# # Get or create Engagement for this repo
# ENGAGEMENT_ID=$(curl -s -H "$AUTH_HEADER" "$DOJO_URL/api/v2/engagements/?product=$PRODUCT_ID&name=$ENGAGEMENT_NAME" | \
#   jq -r '.results[0].id')

# if [ -z "$ENGAGEMENT_ID" ] || [ "$ENGAGEMENT_ID" == "null" ]; then
#   echo "📁 Creating engagement '$ENGAGEMENT_NAME'..."
#   ENGAGEMENT_ID=$(curl -s -X POST "$DOJO_URL/api/v2/engagements/" \
#     -H "$AUTH_HEADER" -H "$JSON_HEADER" \
#     -d "{
#       \"product\": $PRODUCT_ID,
#       \"name\": \"$ENGAGEMENT_NAME\",
#       \"target_start\": \"$DATE\",
#       \"target_end\": \"$END_DATE\",
#       \"status\": \"In Progress\",
#       \"engagement_type\": \"CI/CD\"
#     }" | jq -r '.id')

#   if [ -z "$ENGAGEMENT_ID" ] || [ "$ENGAGEMENT_ID" == "null" ]; then
#     echo "❌ Failed to create engagement."
#     exit 1
#   fi
# fi

# # Upload or reimport scan
# #TEST_TITLE="$BRANCH_NAME - $DATE"
# TEST_TITLE="$BRANCH_NAME"

# curl -s -X POST "$DOJO_URL/api/v2/reimport-scan/" \
#   -H "$AUTH_HEADER" \
#   -F "scan_date=$DATE" \
#   -F "scan_type=Gitleaks Scan" \
#   -F "active=true" \
#   -F "verified=true" \
#   -F "product_name=$PRODUCT_NAME" \
#   -F "engagement_name=$ENGAGEMENT_NAME" \
#   -F "test_title=$TEST_TITLE" \
#   -F "auto_create_context=true" \
#   -F "deduplication_on_engagement=true" \
#   -F "close_old_findings=true" \
#   -F "engagement_end_date=$(date -d '+365 days' +%F)" \
#   -F "file=@$SCAN_FILE"

# echo "✅ Scan uploaded to engagement '$ENGAGEMENT_NAME' with test title '$TEST_TITLE'"


