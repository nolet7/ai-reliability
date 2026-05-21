#!/usr/bin/env bash

# scripts/validate_prediction_audit.sh
#
# Purpose:
# Sends a test prediction request and validates that audit evidence is created.
#
# This script checks:
# - request_id
# - trace_id
# - model_name
# - model_version
# - audit_required
# - audit_logged
#
# Why it matters:
# This proves the service can connect user-facing prediction activity to
# operational evidence needed for Dynatrace, ServiceNow, RCA, and release gates.

set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"
TRACE_ID="${TRACE_ID:-local-trace-phase2-001}"

echo "Validating prediction audit against: ${BASE_URL}"
echo

RESPONSE_FILE="$(mktemp)"

curl -s -X POST "${BASE_URL}/predict" \
  -H "Content-Type: application/json" \
  -H "x-trace-id: ${TRACE_ID}" \
  -d '{
    "asset_id": "asset-1001",
    "site_id": "site-as-poc-001",
    "sensor_score": 87.5,
    "audit_required": true
  }' > "${RESPONSE_FILE}"

echo "Prediction response:"
cat "${RESPONSE_FILE}" | python -m json.tool

echo
echo "Validating required audit fields..."

python - "${RESPONSE_FILE}" "${TRACE_ID}" <<'PY'
import json
import sys

response_file = sys.argv[1]
expected_trace_id = sys.argv[2]

with open(response_file, "r", encoding="utf-8") as f:
    data = json.load(f)

required_fields = [
    "request_id",
    "trace_id",
    "service_name",
    "environment",
    "model_name",
    "model_version",
    "artifact_loaded",
    "prediction_status",
    "audit_required",
    "audit_logged",
    "timestamp_utc",
]

missing = [field for field in required_fields if field not in data]

if missing:
    raise SystemExit(f"Missing required fields: {missing}")

if data["trace_id"] != expected_trace_id:
    raise SystemExit(f"Trace ID mismatch. Expected {expected_trace_id}, got {data['trace_id']}")

if data["service_name"] != "as-ai-quality-service":
    raise SystemExit(f"Unexpected service_name: {data['service_name']}")

if data["model_name"] != "as-quality-classifier":
    raise SystemExit(f"Unexpected model_name: {data['model_name']}")

if data["artifact_loaded"] is not True:
    raise SystemExit("artifact_loaded is not true")

if data["prediction_status"] != "success":
    raise SystemExit(f"Unexpected prediction_status: {data['prediction_status']}")

if data["audit_required"] is not True:
    raise SystemExit("audit_required is not true")

if data["audit_logged"] is not True:
    raise SystemExit("audit_logged is not true")

print("Prediction audit validation passed.")
PY

echo
echo "Checking local audit file..."

if [ ! -f "local/generated/audit/prediction_audit.jsonl" ]; then
  echo "Audit file was not created."
  exit 1
fi

tail -n 1 local/generated/audit/prediction_audit.jsonl | python -m json.tool

rm -f "${RESPONSE_FILE}"

echo
echo "Prediction audit validation completed successfully."
