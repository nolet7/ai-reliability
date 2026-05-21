#!/usr/bin/env bash

# scripts/validate_kubernetes_runtime.sh
#
# Purpose:
# Validates the ASR AI quality service running in Kubernetes.
#
# This script proves:
# - Namespace exists
# - Deployment exists
# - Pods are Running and Ready
# - Service has a LoadBalancer external IP
# - Endpoints exist
# - Health endpoints work
# - Model readiness works
# - Prediction audit works
# - Latency simulation works
# - Controlled error simulation works
# - Logs show runtime traffic
#
# This script is Phase 5 Kubernetes runtime evidence for the POC.

set -euo pipefail

NAMESPACE="${NAMESPACE:-ai-reliability-poc}"
APP_NAME="${APP_NAME:-asr-ai-quality-service}"
TRACE_ID="${TRACE_ID:-k8s-runtime-trace-001}"

echo "============================================================"
echo "ASR AI Reliability POC - Kubernetes Runtime Validation"
echo "============================================================"
echo "Namespace: ${NAMESPACE}"
echo "Application: ${APP_NAME}"
echo

echo "Step 1: Checking Kubernetes context..."
kubectl config current-context
echo

echo "Step 2: Checking namespace..."
kubectl get ns "${NAMESPACE}"
echo

echo "Step 3: Checking deployment..."
kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}"
echo

echo "Step 4: Checking rollout status..."
kubectl rollout status deployment/"${APP_NAME}" -n "${NAMESPACE}"
echo

echo "Step 5: Checking pods..."
kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name="${APP_NAME}" -o wide
echo

READY_PODS="$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name="${APP_NAME}" --no-headers | awk '$2=="1/1" && $3=="Running" {count++} END {print count+0}')"

if [ "${READY_PODS}" -lt 1 ]; then
  echo "No ready pods found for ${APP_NAME}."
  exit 1
fi

echo "Ready pods found: ${READY_PODS}"
echo

echo "Step 6: Checking Service..."
kubectl get svc "${APP_NAME}" -n "${NAMESPACE}"
echo

EXTERNAL_IP="$(kubectl get svc "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"

if [ -z "${EXTERNAL_IP}" ]; then
  echo "LoadBalancer external IP not found."
  echo "Run: kubectl get svc ${APP_NAME} -n ${NAMESPACE}"
  exit 1
fi

BASE_URL="http://${EXTERNAL_IP}"

echo "LoadBalancer IP: ${EXTERNAL_IP}"
echo "Base URL: ${BASE_URL}"
echo

echo "Step 7: Checking Service endpoints..."
kubectl get endpoints "${APP_NAME}" -n "${NAMESPACE}"
echo

ENDPOINTS="$(kubectl get endpoints "${APP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.subsets[*].addresses[*].ip}')"

if [ -z "${ENDPOINTS}" ]; then
  echo "No service endpoints found."
  exit 1
fi

echo "Service endpoints: ${ENDPOINTS}"
echo

echo "Step 8: Testing root endpoint..."
curl -s "${BASE_URL}/" | python -m json.tool
echo

echo "Step 9: Testing health endpoints..."
curl -s "${BASE_URL}/health/live" | python -m json.tool
curl -s "${BASE_URL}/health/ready" | python -m json.tool
curl -s "${BASE_URL}/health/model" | python -m json.tool
echo

echo "Step 10: Testing version endpoint..."
curl -s "${BASE_URL}/version" | python -m json.tool
echo

echo "Step 11: Testing prediction audit..."
RESPONSE_FILE="$(mktemp)"

curl -s -X POST "${BASE_URL}/predict" \
  -H "Content-Type: application/json" \
  -H "x-trace-id: ${TRACE_ID}" \
  -d '{
    "asset_id": "asset-k8s-runtime-1001",
    "site_id": "site-asr-poc-001",
    "sensor_score": 90.5,
    "audit_required": true
  }' > "${RESPONSE_FILE}"

cat "${RESPONSE_FILE}" | python -m json.tool
echo

echo "Step 12: Validating prediction response fields..."
python - "${RESPONSE_FILE}" "${TRACE_ID}" <<'PY'
import json
import sys

response_file = sys.argv[1]
expected_trace_id = sys.argv[2]

with open(response_file, "r", encoding="utf-8") as f:
    data = json.load(f)

checks = {
    "service_name": "asr-ai-quality-service",
    "environment": "poc",
    "model_name": "asr-quality-classifier",
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

print("Prediction audit validation passed.")
PY

echo

echo "Step 13: Testing latency simulation..."
time curl -s "${BASE_URL}/simulate-latency?seconds=1" | python -m json.tool
echo

echo "Step 14: Testing controlled error simulation..."
HTTP_STATUS="$(curl -s -o /tmp/asr_k8s_error.json -w "%{http_code}" "${BASE_URL}/simulate-error")"

echo "HTTP status: ${HTTP_STATUS}"
cat /tmp/asr_k8s_error.json | python -m json.tool || cat /tmp/asr_k8s_error.json

if [ "${HTTP_STATUS}" != "500" ]; then
  echo "Expected HTTP 500 but got ${HTTP_STATUS}"
  exit 1
fi

echo

echo "Step 15: Checking recent pod logs..."
kubectl logs -n "${NAMESPACE}" -l app.kubernetes.io/name="${APP_NAME}" --tail=80
echo

rm -f "${RESPONSE_FILE}"
rm -f /tmp/asr_k8s_error.json

echo "============================================================"
echo "Kubernetes runtime validation completed successfully."
echo "============================================================"
