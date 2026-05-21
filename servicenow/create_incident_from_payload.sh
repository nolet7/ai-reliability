#!/usr/bin/env bash

# servicenow/create_incident_from_payload.sh
#
# Purpose:
# Creates a ServiceNow incident from a JSON payload file.
#
# Features:
# - Dry-run mode by default.
# - Windows/Git Bash safe temp files.
# - Uses --ssl-no-revoke for ServiceNow developer POC.
# - Checks for existing incident by correlation_id.
# - Avoids duplicate incidents.

set -euo pipefail

PAYLOAD_FILE="${1:-}"
DRY_RUN="${DRY_RUN:-true}"

WORK_DIR="local/generated/servicenow"
mkdir -p "${WORK_DIR}"

PRETTY_PAYLOAD_FILE="${WORK_DIR}/payload-preview.json"
EXISTING_FILE="${WORK_DIR}/existing-incident-lookup.json"
RESPONSE_FILE="${WORK_DIR}/servicenow-create-response.json"
STATUS_FILE="${WORK_DIR}/servicenow-http-status.txt"
POST_FAILURE_LOOKUP_FILE="${WORK_DIR}/post-failure-lookup.json"

if [ -z "${PAYLOAD_FILE}" ]; then
  echo "Usage: $0 <payload-json-file>"
  exit 1
fi

if [ ! -f "${PAYLOAD_FILE}" ]; then
  echo "Payload file not found: ${PAYLOAD_FILE}"
  exit 1
fi

echo "============================================================"
echo "ASR AI Reliability POC - ServiceNow Incident Creation"
echo "============================================================"
echo "Payload file: ${PAYLOAD_FILE}"
echo "Dry run: ${DRY_RUN}"
echo

echo "Step 1: Validating JSON payload..."
python -m json.tool "${PAYLOAD_FILE}" > "${PRETTY_PAYLOAD_FILE}"
echo "JSON payload is valid."
echo

echo "Step 2: Payload preview..."
cat "${PRETTY_PAYLOAD_FILE}"
echo

CORRELATION_ID="$(python - <<PY
import json
with open("${PAYLOAD_FILE}", "r", encoding="utf-8") as f:
    data = json.load(f)
print(data.get("correlation_id", ""))
PY
)"

if [ "${DRY_RUN}" = "true" ]; then
  echo "DRY_RUN=true, so no ServiceNow incident was created."
  echo "Dry-run completed successfully."
  exit 0
fi

echo "Step 3: Checking required ServiceNow environment variables..."

: "${SERVICENOW_INSTANCE_URL:?SERVICENOW_INSTANCE_URL is required}"
: "${SERVICENOW_USERNAME:?SERVICENOW_USERNAME is required}"
: "${SERVICENOW_PASSWORD:?SERVICENOW_PASSWORD is required}"

SERVICENOW_INSTANCE_URL="${SERVICENOW_INSTANCE_URL%/}"
SERVICENOW_API_URL="${SERVICENOW_INSTANCE_URL}/api/now/table/incident"

echo "ServiceNow URL: ${SERVICENOW_INSTANCE_URL}"
echo "ServiceNow API: ${SERVICENOW_API_URL}"
echo "Username set: yes"
echo "Password set: yes"
echo

if [ -n "${CORRELATION_ID}" ]; then
  echo "Step 4: Checking whether an incident already exists for correlation_id=${CORRELATION_ID}..."

  QUERY_URL="${SERVICENOW_API_URL}?sysparm_query=correlation_id=${CORRELATION_ID}&sysparm_fields=number,sys_id,short_description,correlation_id&sysparm_limit=1"

  curl -sS \
    --ssl-no-revoke \
    --connect-timeout 20 \
    --max-time 60 \
    -u "${SERVICENOW_USERNAME}:${SERVICENOW_PASSWORD}" \
    -H "Accept: application/json" \
    -X GET \
    "${QUERY_URL}" \
    -o "${EXISTING_FILE}"

  EXISTING_NUMBER="$(python - <<PY
import json
from pathlib import Path

p = Path("${EXISTING_FILE}")
data = json.loads(p.read_text(encoding="utf-8"))
result = data.get("result", [])
print(result[0].get("number", "") if result else "")
PY
)"

  if [ -n "${EXISTING_NUMBER}" ]; then
    echo "Incident already exists: ${EXISTING_NUMBER}"
    echo "No duplicate incident created."
    echo "============================================================"
    echo "ServiceNow incident already existed. Treating as success."
    echo "============================================================"
    exit 0
  fi
fi

echo "Step 5: Sending incident to ServiceNow..."

curl -sS \
  --ssl-no-revoke \
  --connect-timeout 20 \
  --max-time 120 \
  -u "${SERVICENOW_USERNAME}:${SERVICENOW_PASSWORD}" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -X POST \
  "${SERVICENOW_API_URL}" \
  --data @"${PAYLOAD_FILE}" \
  -o "${RESPONSE_FILE}" \
  -w "%{http_code}" > "${STATUS_FILE}"

HTTP_STATUS="$(cat "${STATUS_FILE}")"

echo "HTTP status: ${HTTP_STATUS}"
echo

echo "ServiceNow response:"
cat "${RESPONSE_FILE}" | python -m json.tool || cat "${RESPONSE_FILE}"
echo

if [ "${HTTP_STATUS}" = "200" ] || [ "${HTTP_STATUS}" = "201" ]; then
  INCIDENT_NUMBER="$(python - <<PY
import json
from pathlib import Path

data = json.loads(Path("${RESPONSE_FILE}").read_text(encoding="utf-8"))
result = data.get("result", {})
print(result.get("number", "UNKNOWN"))
PY
)"
  echo "============================================================"
  echo "ServiceNow incident created successfully: ${INCIDENT_NUMBER}"
  echo "============================================================"
  exit 0
fi

echo "ServiceNow returned non-success status."

if [ -n "${CORRELATION_ID}" ]; then
  echo "Checking whether incident was still created despite API response failure..."

  QUERY_URL="${SERVICENOW_API_URL}?sysparm_query=correlation_id=${CORRELATION_ID}&sysparm_fields=number,sys_id,short_description,correlation_id&sysparm_limit=1"

  curl -sS \
    --ssl-no-revoke \
    --connect-timeout 20 \
    --max-time 60 \
    -u "${SERVICENOW_USERNAME}:${SERVICENOW_PASSWORD}" \
    -H "Accept: application/json" \
    -X GET \
    "${QUERY_URL}" \
    -o "${POST_FAILURE_LOOKUP_FILE}"

  FOUND_NUMBER="$(python - <<PY
import json
from pathlib import Path

data = json.loads(Path("${POST_FAILURE_LOOKUP_FILE}").read_text(encoding="utf-8"))
result = data.get("result", [])
print(result[0].get("number", "") if result else "")
PY
)"

  if [ -n "${FOUND_NUMBER}" ]; then
    echo "Incident was created despite API response failure: ${FOUND_NUMBER}"
    echo "============================================================"
    echo "Treating as success because incident exists in ServiceNow."
    echo "============================================================"
    exit 0
  fi
fi

echo "ServiceNow incident creation failed and no matching incident was found."
exit 1
