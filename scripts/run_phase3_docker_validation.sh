#!/usr/bin/env bash

# scripts/run_phase3_docker_validation.sh
#
# Purpose:
# Validates the AS AI Quality Service running inside Docker.
#
# This script proves:
# - Docker container is running
# - Docker host port is reachable
# - Health endpoints work
# - Model readiness works
# - Prediction audit works
# - Audit file exists inside the container
# - Latency simulation works
# - Error simulation works
# - Docker health check is healthy
#
# This script becomes Phase 3 evidence for the POC.

set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-as-ai-quality-service-poc}"
BASE_URL="${BASE_URL:-http://127.0.0.1:8010}"
TRACE_ID="${TRACE_ID:-docker-trace-phase3-001}"

echo "============================================================"
echo "AS AI Reliability POC - Phase 3 Docker Validation"
echo "============================================================"
echo "Container: ${CONTAINER_NAME}"
echo "Base URL: ${BASE_URL}"
echo

echo "Step 1: Checking container is running..."
docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}"

if ! docker ps --filter "name=${CONTAINER_NAME}" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
  echo "Container ${CONTAINER_NAME} is not running."
  exit 1
fi

echo
echo "Step 2: Checking app routes inside the container..."
docker exec "${CONTAINER_NAME}" \
  python -c "import app.main as m; print(m.SERVICE_NAME); print(m.MODEL_NAME); print([r.path for r in m.app.routes])"

echo
echo "Step 3: Testing root endpoint from host..."
curl -s "${BASE_URL}/" | python -m json.tool

echo
echo "Step 4: Testing health endpoints..."
curl -s "${BASE_URL}/health/live" | python -m json.tool
curl -s "${BASE_URL}/health/ready" | python -m json.tool
curl -s "${BASE_URL}/health/model" | python -m json.tool

echo
echo "Step 5: Testing version endpoint..."
curl -s "${BASE_URL}/version" | python -m json.tool

echo
echo "Step 6: Testing prediction audit..."
RESPONSE_FILE="$(mktemp)"

curl -s -X POST "${BASE_URL}/predict" \
  -H "Content-Type: application/json" \
  -H "x-trace-id: ${TRACE_ID}" \
  -d '{
    "asset_id": "asset-3001",
    "site_id": "site-as-poc-001",
    "sensor_score": 92.4,
    "audit_required": true
  }' > "${RESPONSE_FILE}"

cat "${RESPONSE_FILE}" | python -m json.tool

echo
echo "Step 7: Validating prediction response fields..."
python - "${RESPONSE_FILE}" "${TRACE_ID}" <<'PY'
import json
import sys

response_file = sys.argv[1]
expected_trace_id = sys.argv[2]

with open(response_file, "r", encoding="utf-8") as f:
    data = json.load(f)

checks = {
    "service_name": "as-ai-quality-service",
    "environment": "poc",
    "model_name": "as-quality-classifier",
    "model_version": "v1.0.3",
    "trace_id": expected_trace_id,
    "prediction_status": "success",
}

for key, expected in checks.items():
    actual = data.get(key)
    if actual != expected:
        raise SystemExit(f"{key} expected {expected}, got {actual}")

if data.get("artifact_loaded") is not True:
    raise SystemExit("artifact_loaded is not true")

if data.get("audit_required") is not True:
    raise SystemExit("audit_required is not true")

if data.get("audit_logged") is not True:
    raise SystemExit("audit_logged is not true")

print("Prediction response validation passed.")
PY

echo
echo "Step 8: Checking audit file inside container..."
docker exec "${CONTAINER_NAME}" sh -c "ls -l /app/local/generated/audit"

echo
echo "Latest audit record inside container:"
docker exec "${CONTAINER_NAME}" sh -c "tail -n 1 /app/local/generated/audit/prediction_audit.jsonl" | python -m json.tool

echo
echo "Step 9: Validating latest audit file record..."
docker exec "${CONTAINER_NAME}" sh -c "tail -n 1 /app/local/generated/audit/prediction_audit.jsonl" > /tmp/as_phase3_audit_record.json

python - "/tmp/as_phase3_audit_record.json" "${TRACE_ID}" <<'PY'
import json
import sys

audit_file = sys.argv[1]
expected_trace_id = sys.argv[2]

with open(audit_file, "r", encoding="utf-8") as f:
    data = json.load(f)

if data.get("trace_id") != expected_trace_id:
    raise SystemExit(f"trace_id expected {expected_trace_id}, got {data.get('trace_id')}")

if data.get("service_name") != "as-ai-quality-service":
    raise SystemExit(f"Unexpected service_name: {data.get('service_name')}")

if data.get("model_name") != "as-quality-classifier":
    raise SystemExit(f"Unexpected model_name: {data.get('model_name')}")

if data.get("audit_required") is not True:
    raise SystemExit("audit_required is not true in audit file")

if data.get("audit_logged") is not True:
    raise SystemExit("audit_logged is not true in audit file")

print("Audit file validation passed.")
PY

echo
echo "Step 10: Testing latency simulation..."
time curl -s "${BASE_URL}/simulate-latency?seconds=1" | python -m json.tool

echo
echo "Step 11: Testing controlled error simulation..."
HTTP_STATUS="$(curl -s -o /tmp/as_phase3_error.json -w "%{http_code}" "${BASE_URL}/simulate-error")"

echo "HTTP status: ${HTTP_STATUS}"
cat /tmp/as_phase3_error.json | python -m json.tool || cat /tmp/as_phase3_error.json

if [ "${HTTP_STATUS}" != "500" ]; then
  echo "Expected HTTP 500 but got ${HTTP_STATUS}"
  exit 1
fi

echo
echo "Step 12: Checking Docker health status..."
docker inspect --format='{{json .State.Health}}' "${CONTAINER_NAME}" | python -m json.tool

HEALTH_STATUS="$(docker inspect --format='{{.State.Health.Status}}' "${CONTAINER_NAME}")"

if [ "${HEALTH_STATUS}" != "healthy" ]; then
  echo "Expected Docker health status healthy but got ${HEALTH_STATUS}"
  exit 1
fi

rm -f "${RESPONSE_FILE}"
rm -f /tmp/as_phase3_audit_record.json
rm -f /tmp/as_phase3_error.json

echo
echo "============================================================"
echo "Phase 3 Docker validation completed successfully."
echo "============================================================"
