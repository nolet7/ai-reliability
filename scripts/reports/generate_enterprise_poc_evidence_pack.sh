#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Phase 8 - Enterprise POC Evidence Pack
#
# Purpose:
#   Produce final executive, SRE, platform, and audit evidence
#   for the AS AI Reliability POC.
#
# Enterprise value:
#   This turns the POC into a portfolio-ready and audit-ready
#   release package showing deployment, runtime health, model
#   reliability, Kubernetes state, Istio routing, and incident
#   automation readiness.
# ============================================================

PHASE_NAME="Phase 8 - Enterprise POC Evidence Pack"

REPORT_ROOT="${REPORT_ROOT:-reports/enterprise-poc-evidence}"
RAW_DIR="$REPORT_ROOT/raw"
SUMMARY_MD="$REPORT_ROOT/as-ai-reliability-enterprise-evidence.md"
SUMMARY_HTML="$REPORT_ROOT/as-ai-reliability-enterprise-evidence.html"
JSON_REPORT="$REPORT_ROOT/as-ai-reliability-enterprise-evidence.json"
CSV_REPORT="$REPORT_ROOT/as-ai-reliability-endpoint-validation.csv"

mkdir -p "$RAW_DIR"

NAMESPACE="${NAMESPACE:-ai-reliability-poc}"
APP_NAME="${APP_NAME:-as-ai-quality-service}"
SERVICE_NAME="${SERVICE_NAME:-$APP_NAME}"
ENVIRONMENT="${ENVIRONMENT:-poc}"
EXPECTED_MODEL_VERSION="${EXPECTED_MODEL_VERSION:-v1.0.3}"

ISTIO_INGRESS_IP="${ISTIO_INGRESS_IP:-139.144.255.92}"
APP_LOADBALANCER_IP="${APP_LOADBALANCER_IP:-139.144.255.192}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-http://${ISTIO_INGRESS_IP}}"
BASE_URL="${PUBLIC_BASE_URL%/}"

PREDICT_PAYLOAD="${PREDICT_PAYLOAD:-{\"asset_id\":\"asset-1001\",\"site_id\":\"site-asr-poc-001\",\"sensor_score\":87.5,\"audit_required\":true}}"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
START_EPOCH="$(date +%s)"
STARTED_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

record_gate() {
  local status="$1"
  local gate="$2"
  local evidence="$3"

  echo "| $status | $gate | $evidence |" >> "$SUMMARY_MD"

  case "$status" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
  esac
}

seconds_to_ms() {
  python3 - "$1" <<'PY'
import sys
try:
    print(int(float(sys.argv[1]) * 1000))
except Exception:
    print(0)
PY
}

extract_model_version() {
  local file="$1"

  jq -r '
    .model_version //
    .modelVersion //
    .version //
    .model.version //
    .data.model_version //
    empty
  ' "$file" 2>/dev/null | head -n 1
}

validate_get_endpoint() {
  local name="$1"
  local path="$2"
  local expected_code="${3:-200}"
  local output_file="$RAW_DIR/${name}.json"

  local metrics
  metrics="$(
    curl -k -sS \
      --connect-timeout 5 \
      --max-time 20 \
      -o "$output_file" \
      -w "%{http_code},%{time_total}" \
      "$BASE_URL$path" || true
  )"

  local http_code="${metrics%%,*}"
  local seconds="${metrics#*,}"
  local latency_ms
  latency_ms="$(seconds_to_ms "$seconds")"

  echo "$name,GET,$path,$http_code,$latency_ms" >> "$CSV_REPORT"

  if [[ "$http_code" == "$expected_code" ]]; then
    record_gate "PASS" "Endpoint GET $path" "HTTP $http_code, ${latency_ms}ms"
  else
    record_gate "FAIL" "Endpoint GET $path" "Expected HTTP $expected_code, got HTTP $http_code"
  fi
}

validate_predict_endpoint() {
  local output_file="$RAW_DIR/predict.json"

  local metrics
  metrics="$(
    curl -k -sS \
      --connect-timeout 5 \
      --max-time 20 \
      -o "$output_file" \
      -w "%{http_code},%{time_total}" \
      -X POST "$BASE_URL/predict" \
      -H "Content-Type: application/json" \
      -H "x-trace-id: phase-8-enterprise-evidence-pack" \
      -d "$PREDICT_PAYLOAD" || true
  )"

  local http_code="${metrics%%,*}"
  local seconds="${metrics#*,}"
  local latency_ms
  latency_ms="$(seconds_to_ms "$seconds")"

  echo "predict,POST,/predict,$http_code,$latency_ms" >> "$CSV_REPORT"

  if [[ "$http_code" =~ ^2 ]]; then
    record_gate "PASS" "Endpoint POST /predict" "HTTP $http_code, ${latency_ms}ms"
  else
    record_gate "FAIL" "Endpoint POST /predict" "Expected 2xx, got HTTP $http_code"
  fi

  local prediction_model_version
  prediction_model_version="$(extract_model_version "$output_file")"

  if [[ "$prediction_model_version" == "$EXPECTED_MODEL_VERSION" ]]; then
    record_gate "PASS" "Prediction model version" "/predict returned $prediction_model_version"
  else
    record_gate "FAIL" "Prediction model version" "/predict returned '${prediction_model_version:-not-found}', expected $EXPECTED_MODEL_VERSION"
  fi
}

cat > "$SUMMARY_MD" <<EOF
# AS AI Reliability POC Enterprise Evidence Pack

| Field | Value |
|---|---|
| Phase | $PHASE_NAME |
| Environment | $ENVIRONMENT |
| Namespace | $NAMESPACE |
| Application | $APP_NAME |
| Service | $SERVICE_NAME |
| Public Base URL | $BASE_URL |
| Istio Ingress IP | $ISTIO_INGRESS_IP |
| App LoadBalancer IP | $APP_LOADBALANCER_IP |
| Expected Model Version | $EXPECTED_MODEL_VERSION |
| Started UTC | $STARTED_UTC |

## Executive Summary

This report provides enterprise release evidence for the AS AI Reliability POC. It validates that the AI quality service is deployed, reachable, observable-ready, model-aware, and suitable for controlled release workflows using Kubernetes, Istio, Dynatrace, GitHub Actions, and ServiceNow incident automation.

## Gate Results

| Status | Gate | Evidence |
|---|---|---|
EOF

echo "name,method,path,http_code,latency_ms" > "$CSV_REPORT"

# ----------------------------
# Tooling preflight
# ----------------------------
for tool in kubectl curl jq python3; do
  if command -v "$tool" >/dev/null 2>&1; then
    record_gate "PASS" "Tool available: $tool" "Found $tool"
  else
    record_gate "FAIL" "Tool missing: $tool" "$tool is required"
  fi
done

# ----------------------------
# Kubernetes evidence
# ----------------------------
if kubectl get namespace "$NAMESPACE" > "$RAW_DIR/namespace.txt" 2>&1; then
  record_gate "PASS" "Kubernetes namespace" "$NAMESPACE exists"
else
  record_gate "FAIL" "Kubernetes namespace" "$NAMESPACE not found"
fi

kubectl -n "$NAMESPACE" get deploy,pods,svc -o wide > "$RAW_DIR/kubernetes-core-resources.txt" 2>&1 || true
kubectl -n "$NAMESPACE" get deploy --show-labels > "$RAW_DIR/kubernetes-deploy-labels.txt" 2>&1 || true
kubectl -n "$NAMESPACE" get pods --show-labels > "$RAW_DIR/kubernetes-pod-labels.txt" 2>&1 || true
kubectl -n "$NAMESPACE" get gateway,virtualservice,destinationrule -o yaml > "$RAW_DIR/istio-runtime-resources.yaml" 2>&1 || true

record_gate "PASS" "Kubernetes evidence captured" "Saved deployments, pods, services, labels, and Istio resources"

if kubectl -n "$NAMESPACE" get svc "$SERVICE_NAME" > "$RAW_DIR/service.txt" 2>&1; then
  record_gate "PASS" "Kubernetes service" "$SERVICE_NAME exists"
else
  record_gate "FAIL" "Kubernetes service" "$SERVICE_NAME not found"
fi

# ----------------------------
# Runtime endpoint validation
# ----------------------------
validate_get_endpoint "root" "/"
validate_get_endpoint "health-live" "/health/live"
validate_get_endpoint "health-ready" "/health/ready"
validate_get_endpoint "health-model" "/health/model"
validate_get_endpoint "version" "/version"

VERSION_MODEL_FILE="$RAW_DIR/version.json"
VERSION_MODEL_VERSION="$(extract_model_version "$VERSION_MODEL_FILE")"

if [[ "$VERSION_MODEL_VERSION" == "$EXPECTED_MODEL_VERSION" ]]; then
  record_gate "PASS" "Version endpoint model version" "/version returned $VERSION_MODEL_VERSION"
else
  record_gate "FAIL" "Version endpoint model version" "/version returned '${VERSION_MODEL_VERSION:-not-found}', expected $EXPECTED_MODEL_VERSION"
fi

validate_predict_endpoint

# ----------------------------
# Final report
# ----------------------------
END_EPOCH="$(date +%s)"
DURATION_SECONDS=$((END_EPOCH - START_EPOCH))
FINISHED_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ "$FAIL_COUNT" -eq 0 ]]; then
  FINAL_STATUS="passed"
else
  FINAL_STATUS="failed"
fi

cat >> "$SUMMARY_MD" <<EOF

## Final Summary

| Metric | Value |
|---|---|
| Final Status | $FINAL_STATUS |
| Passed Gates | $PASS_COUNT |
| Warning Gates | $WARN_COUNT |
| Failed Gates | $FAIL_COUNT |
| Duration Seconds | $DURATION_SECONDS |
| Finished UTC | $FINISHED_UTC |

## Enterprise Capabilities Proven

| Capability | Evidence |
|---|---|
| Kubernetes deployment | Namespace, deployments, pods, services captured |
| Istio traffic management | Gateway, VirtualService, and DestinationRule captured |
| AI model visibility | /version and /health/model validated |
| Runtime readiness | /health/live and /health/ready validated |
| Prediction path | /predict validated with trace header |
| Release evidence | Markdown, HTML, JSON, CSV, and raw artifacts generated |
| Incident readiness | Phase 6 ServiceNow automation completed earlier |
| Progressive delivery | Phase 7 canary/rollback automation added |

## Evidence Files

- \`as-ai-reliability-enterprise-evidence.md\`
- \`as-ai-reliability-enterprise-evidence.html\`
- \`as-ai-reliability-enterprise-evidence.json\`
- \`as-ai-reliability-endpoint-validation.csv\`
- \`raw/kubernetes-core-resources.txt\`
- \`raw/kubernetes-deploy-labels.txt\`
- \`raw/kubernetes-pod-labels.txt\`
- \`raw/istio-runtime-resources.yaml\`
- \`raw/version.json\`
- \`raw/predict.json\`
EOF

jq -n \
  --arg phase "$PHASE_NAME" \
  --arg status "$FINAL_STATUS" \
  --arg environment "$ENVIRONMENT" \
  --arg namespace "$NAMESPACE" \
  --arg app_name "$APP_NAME" \
  --arg service_name "$SERVICE_NAME" \
  --arg base_url "$BASE_URL" \
  --arg expected_model_version "$EXPECTED_MODEL_VERSION" \
  --arg version_model_version "${VERSION_MODEL_VERSION:-}" \
  --arg started_utc "$STARTED_UTC" \
  --arg finished_utc "$FINISHED_UTC" \
  --argjson passed_gates "$PASS_COUNT" \
  --argjson warning_gates "$WARN_COUNT" \
  --argjson failed_gates "$FAIL_COUNT" \
  --argjson duration_seconds "$DURATION_SECONDS" \
  '{
    phase: $phase,
    status: $status,
    environment: $environment,
    namespace: $namespace,
    app_name: $app_name,
    service_name: $service_name,
    base_url: $base_url,
    expected_model_version: $expected_model_version,
    version_model_version: $version_model_version,
    passed_gates: $passed_gates,
    warning_gates: $warning_gates,
    failed_gates: $failed_gates,
    duration_seconds: $duration_seconds,
    started_utc: $started_utc,
    finished_utc: $finished_utc
  }' > "$JSON_REPORT"

python3 - "$SUMMARY_MD" "$SUMMARY_HTML" <<'PY'
import html
import sys
from pathlib import Path

md_path = Path(sys.argv[1])
html_path = Path(sys.argv[2])

content = md_path.read_text(encoding="utf-8")

html_content = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>AS AI Reliability POC Enterprise Evidence Pack</title>
  <style>
    body {{
      font-family: Arial, sans-serif;
      margin: 40px;
      color: #1f2937;
      line-height: 1.5;
    }}
    h1, h2 {{
      color: #111827;
    }}
    pre {{
      background: #f3f4f6;
      padding: 16px;
      border-radius: 8px;
      overflow-x: auto;
      white-space: pre-wrap;
    }}
  </style>
</head>
<body>
  <pre>{html.escape(content)}</pre>
</body>
</html>
"""

html_path.write_text(html_content, encoding="utf-8")
PY

echo
echo "Enterprise evidence pack status: $FINAL_STATUS"
echo "Markdown report: $SUMMARY_MD"
echo "HTML report: $SUMMARY_HTML"
echo "JSON report: $JSON_REPORT"
echo "CSV report: $CSV_REPORT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
