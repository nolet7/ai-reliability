#!/usr/bin/env bash

# scripts/run_release_gates.sh
#
# Purpose:
# Runs ASR AI Reliability POC release gates.
#
# These gates validate:
# - Kubernetes rollout health
# - Pod readiness
# - Health endpoints
# - Model readiness
# - Prediction audit
# - Atlas schema drift status
# - Istio rollback safety
#
# If any required gate fails, this script exits with code 1.
# Later, this can trigger ServiceNow release-gate incident creation.

set -euo pipefail

NAMESPACE="${NAMESPACE:-ai-reliability-poc}"
APP_NAME="${APP_NAME:-asr-ai-quality-service}"
ASR_LB_IP="${ASR_LB_IP:-139.144.255.192}"
ISTIO_INGRESS_IP="${ISTIO_INGRESS_IP:-139.144.255.92}"
EXPECTED_MODEL_VERSION="${EXPECTED_MODEL_VERSION:-v1.0.3}"
TRACE_ID="${TRACE_ID:-release-gate-trace-001}"

BASE_URL="http://${ASR_LB_IP}"
ISTIO_URL="http://${ISTIO_INGRESS_IP}"

echo "============================================================"
echo "ASR AI Reliability POC - Release Gate Validation"
echo "============================================================"
echo "Namespace: ${NAMESPACE}"
echo "Application: ${APP_NAME}"
echo "Base URL: ${BASE_URL}"
echo "Istio URL: ${ISTIO_URL}"
echo "Expected model version: ${EXPECTED_MODEL_VERSION}"
echo

echo "Gate 1: Kubernetes rollout status..."
kubectl rollout status deployment/"${APP_NAME}" -n "${NAMESPACE}"
echo "PASS: Kubernetes rollout is healthy."
echo

echo "Gate 2: Pod readiness..."
kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name="${APP_NAME}" -o wide

READY_PODS="$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name="${APP_NAME}" --no-headers | awk '$2=="2/2" && $3=="Running" {count++} END {print count+0}')"

if [ "${READY_PODS}" -lt 1 ]; then
  echo "FAIL: No Istio-injected ready pods found."
  exit 1
fi

echo "PASS: Ready Istio-injected pods found: ${READY_PODS}"
echo

echo "Gate 3: /health/live..."
curl -s "${BASE_URL}/health/live" | python -m json.tool
echo "PASS: /health/live works."
echo

echo "Gate 4: /health/ready..."
curl -s "${BASE_URL}/health/ready" | python -m json.tool
echo "PASS: /health/ready works."
echo

echo "Gate 5: /health/model..."
MODEL_HEALTH_FILE="$(mktemp)"

curl -s "${BASE_URL}/health/model" > "${MODEL_HEALTH_FILE}"
cat "${MODEL_HEALTH_FILE}" | python -m json.tool

python - "${MODEL_HEALTH_FILE}" "${EXPECTED_MODEL_VERSION}" <<'PY'
import json
import sys

path = sys.argv[1]
expected_model_version = sys.argv[2]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

if data.get("status") != "model_ready":
    raise SystemExit(f"Expected model_ready, got {data.get('status')}")

if data.get("artifact_loaded") is not True:
    raise SystemExit("artifact_loaded is not true")

if data.get("model_version") != expected_model_version:
    raise SystemExit(f"Expected model_version {expected_model_version}, got {data.get('model_version')}")

print("PASS: model readiness validated.")
PY

rm -f "${MODEL_HEALTH_FILE}"
echo

echo "Gate 6: Prediction audit..."
PREDICT_FILE="$(mktemp)"

curl -s -X POST "${BASE_URL}/predict" \
  -H "Content-Type: application/json" \
  -H "x-trace-id: ${TRACE_ID}" \
  -d '{
    "asset_id": "asset-release-gate-1001",
    "site_id": "site-asr-poc-001",
    "sensor_score": 91.5,
    "audit_required": true
  }' > "${PREDICT_FILE}"

cat "${PREDICT_FILE}" | python -m json.tool

python - "${PREDICT_FILE}" "${TRACE_ID}" <<'PY'
import json
import sys

path = sys.argv[1]
expected_trace_id = sys.argv[2]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

if data.get("trace_id") != expected_trace_id:
    raise SystemExit("trace_id mismatch")

if data.get("service_name") != "asr-ai-quality-service":
    raise SystemExit("service_name mismatch")

if data.get("prediction_status") != "success":
    raise SystemExit("prediction_status is not success")

if data.get("audit_required") is not True:
    raise SystemExit("audit_required is not true")

if data.get("audit_logged") is not True:
    raise SystemExit("audit_logged is not true")

print("PASS: prediction audit validated.")
PY

rm -f "${PREDICT_FILE}"
echo

echo "Gate 7: Atlas schema drift check..."
./scripts/run_atlas_drift_check.sh
echo "PASS: Atlas schema drift gate is clean."
echo

echo "Gate 8: Istio rollback safety..."
echo "Validating Istio traffic returns only ${EXPECTED_MODEL_VERSION}..."

TRAFFIC_RESULT_FILE="$(mktemp)"

for i in {1..30}; do
  curl -s "${ISTIO_URL}/version" | python -c "import sys,json; print(json.load(sys.stdin)['model_version'])"
done | sort | uniq -c > "${TRAFFIC_RESULT_FILE}"

cat "${TRAFFIC_RESULT_FILE}"

if grep -q "v1.0.4" "${TRAFFIC_RESULT_FILE}"; then
  echo "FAIL: Canary version v1.0.4 is still receiving traffic during rollback gate."
  rm -f "${TRAFFIC_RESULT_FILE}"
  exit 1
fi

if ! grep -q "${EXPECTED_MODEL_VERSION}" "${TRAFFIC_RESULT_FILE}"; then
  echo "FAIL: Expected model version ${EXPECTED_MODEL_VERSION} not found."
  rm -f "${TRAFFIC_RESULT_FILE}"
  exit 1
fi

rm -f "${TRAFFIC_RESULT_FILE}"

echo "PASS: Istio rollback safety validated."
echo

echo "============================================================"
echo "All release gates passed successfully."
echo "============================================================"
