#!/bin/bash
# ===============================================================================
# File: validate.sh
# ===============================================================================
# Purpose:
#   Validate the Notes API by exercising all CRUD endpoints:
#     - POST   /notes        (create notes)
#     - GET    /notes        (list notes)
#     - GET    /notes/{id}   (get note)
#     - PUT    /notes/{id}   (update note)
#     - DELETE /notes/{id}   (delete note)
#
# Requirements:
#   - aws CLI
#   - curl
#   - jq
#
# Notes:
#   - Assumes an HTTP API named "notes-api"
#   - Owner is hardcoded to "global" in Lambda logic
# ===============================================================================

set -euo pipefail
export AWS_DEFAULT_REGION="us-east-1"

# ------------------------------------------------------------------------------
# Step 1: Discover API Gateway endpoint
# ------------------------------------------------------------------------------
echo "NOTE: Locating API Gateway endpoint..."

API_ID=$(aws apigatewayv2 get-apis \
  --query "Items[?Name=='notes-api'].ApiId" \
  --output text)

if [[ -z "${API_ID}" || "${API_ID}" == "None" ]]; then
  echo "ERROR: No API found with name 'notes-api'"
  exit 1
fi

API_BASE=$(aws apigatewayv2 get-api \
  --api-id "${API_ID}" \
  --query "ApiEndpoint" \
  --output text)

echo "NOTE: API Gateway URL - ${API_BASE}"

# ------------------------------------------------------------------------------
# Step 2: Create 5 notes
# ------------------------------------------------------------------------------
echo "NOTE: Creating 5 test notes..."

NOTE_IDS=()

for i in {1..5}; do
  PAYLOAD=$(jq -n \
    --arg title "Test Note ${i}" \
    --arg note "This is test note ${i}" \
    '{ title: $title, note: $note }')

  RESPONSE=$(curl -s -X POST "${API_BASE}/notes" \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD}")

  NOTE_ID=$(echo "${RESPONSE}" | jq -r '.id // empty')

  if [[ -z "${NOTE_ID}" ]]; then
    echo "ERROR: Failed to create note ${i}"
    echo "RESPONSE: ${RESPONSE}"
    exit 1
  fi

  NOTE_IDS+=("${NOTE_ID}")
  echo "NOTE: Created note ${i} (id=${NOTE_ID})"
done

# ------------------------------------------------------------------------------
# Step 3: List notes
# ------------------------------------------------------------------------------
echo "NOTE: Listing notes..."

LIST_RESPONSE=$(curl -s "${API_BASE}/notes")
NOTE_COUNT=$(echo "${LIST_RESPONSE}" | jq '.items | length')

if [[ "${NOTE_COUNT}" -lt 5 ]]; then
  echo "ERROR: Expected at least 5 notes, got ${NOTE_COUNT}"
  exit 1
fi

echo "NOTE: List endpoint returned ${NOTE_COUNT} notes"

# ------------------------------------------------------------------------------
# Step 4: Get each note by ID
# ------------------------------------------------------------------------------
echo "NOTE: Fetching each created note..."

for ID in "${NOTE_IDS[@]}"; do
  GET_RESPONSE=$(curl -s "${API_BASE}/notes/${ID}")
  TITLE=$(echo "${GET_RESPONSE}" | jq -r '.title // empty')

  if [[ -z "${TITLE}" ]]; then
    echo "ERROR: Failed to fetch note ${ID}"
    exit 1
  fi

  echo "NOTE: Retrieved note ${ID} (${TITLE})"
done

# ------------------------------------------------------------------------------
# Step 5: Update each note
# ------------------------------------------------------------------------------
echo "NOTE: Updating each note..."

for ID in "${NOTE_IDS[@]}"; do
  UPDATE_PAYLOAD=$(jq -n \
    --arg title "Updated ${ID}" \
    '{ title: $title }')

  UPDATE_RESPONSE=$(curl -s -X PUT "${API_BASE}/notes/${ID}" \
    -H "Content-Type: application/json" \
    -d "${UPDATE_PAYLOAD}")

  UPDATED_TITLE=$(echo "${UPDATE_RESPONSE}" | jq -r '.title // empty')

  if [[ -z "${UPDATED_TITLE}" ]]; then
    echo "ERROR: Failed to update note ${ID}"
    exit 1
  fi

  echo "NOTE: Updated note ${ID}"
done

# ------------------------------------------------------------------------------
# Step 6: Delete the first created note
# ------------------------------------------------------------------------------
echo "NOTE: Deleting the first created note..."

if [[ "${#NOTE_IDS[@]}" -gt 0 ]]; then
  FIRST_ID="${NOTE_IDS[0]}"
  curl -s -X DELETE "${API_BASE}/notes/${FIRST_ID}" > /dev/null
  echo "NOTE: Deleted note ${FIRST_ID}"
else
  echo "WARNING: No notes available to delete"
fi

echo "SUCCESS: Notes API validation complete"
