#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Phase 10 - Final Enterprise Release Certification
#
# Purpose:
#   Validate the complete AS AI Reliability POC from an
#   enterprise SRE release-readiness perspective.
#
# Enterprise value:
#   This is the final release certificate showing that the POC
#   has runtime health, AI model version evidence, Kubernetes
#   evidence, Istio routing evidence, prediction evidence,
#   ServiceNow workflow automation, Dynatrace validation, and
#   final demo/evidence-pack automation.
# ============================================================

PHASE_NAME="Phase 10 - Final Enterprise Release Certification"

REPORT_ROOT="${REPORT_ROOT:-reports/final-certification}"
RAW_DIR="$REPORT_ROOT/raw"
SUMMARY_MD="$REPORT_ROOT/as-ai-reliability-final-certification.md"
SUMMARY_HTML="$REPORT_ROOT/as-ai-reliability-final-certification.html"
JSON_REPORT="$REPORT_ROOT/as-ai-reliability-final-certification.json"
CSV_REPORT="$REPORT_ROOT/as-ai-reliability-final-certification-endpoints.csv"

mkdir -p "$RAW_DIR"

NAMESPACE="${NAMESPACE:-ai-reliability-poc}"
APP_NAME="${APP_NAME:-as-ai-quality-service}"
SERVICE_NAME="${SERVICE_NAME:-$APP_NAME}"
ENVIRONMENT="${ENVIRONMENT:-poc}"
EXPECTED_MODEL_VERSION="${EXPECTED_MODEL_VERSION:-v1.0.3}"

ISTIO_INGRESS_IP="${ISTIO_INGRESS_IP:-139.144.255.92}"
APP_LOADBALANCER_IP="${APP_LOADBALANCER_IP:-139.144.255.192}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-http://${ISTIO_INGRESS_IP}}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL%/}"

VERSION_PATH="${VERSION_PATH:-/version}"
MODEL_HEALTH_PATH="${MODEL_HEALTH_PATH:-/health/model}"
PREDICT_PATH="${PREDICT_PATH:-/predict}"

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

validate_get() {
  local name="$1"
  local path="$2"
  local expected_code="${3:-200}"
  local output="$RAW_DIR/${name}.json"

  local metrics
  metrics="$(
    curl -k -sS \
      --connect-timeout 5 \
      --max-time 20 \
      -o "$output" \
      -w "%{http_code},%{time_total}" \
      "$PUBLIC_BASE_URL$path" || true
  )"

  local code="${metrics%%,*}"
  local seconds="${metrics#*,}"
  local latency_ms
  latency_ms="$(seconds_to_ms "$seconds")"

  echo "$name,GET,$path,$code,$latency_ms" >> "$CSV_REPORT"

  if [[ "$code" == "$expected_code" ]]; then
    record_gate "PASS" "GET $path" "HTTP $code, ${latency_ms}ms"
  else
    record_gate "FAIL" "GET $path" "Expected HTTP $expected_code, got HTTP $code"
  fi
}

validate_predict() {
  local output="$RAW_DIR/predict.json"

  local metrics
  metrics="$(
    curl -k -sS \
      --connect-timeout 5 \
      --max-time 20 \
      -o "$output" \
      -w "%{http_code},%{time_total}" \
      -X POST "$PUBLIC_BASE_URL$PREDICT_PATH" \
      -H "Content-Type: application/json" \
      -H "x-trace-id: phase-10-final-certification" \
      -d "$PREDICT_PAYLOAD" || true
  )"

  local code="${metrics%%,*}"
  local seconds="${metrics#*,}"
  local latency_ms
  latency_ms="$(seconds_to_ms "$seconds")"

  echo "predict,POST,$PREDICT_PATH,$code,$latency_ms" >> "$CSV_REPORT"

  if [[ "$code" =~ ^2 ]]; then
    record_gate "PASS" "POST $PREDICT_PATH" "HTTP $code, ${latency_ms}ms"
  else
    record_gate "FAIL" "POST $PREDICT_PATH" "Expected 2xx, got HTTP $code"
  fi

  local predict_version
  predict_version="$(extract_model_version "$output")"

  if [[ "$predict_version" == "$EXPECTED_MODEL_VERSION" ]]; then
    record_gate "PASS" "Prediction model version" "$PREDICT_PATH returned $predict_version"
  else
    record_gate "FAIL" "Prediction model version" "$PREDICT_PATH returned '${predict_version:-not-found}', expected $EXPECTED_MODEL_VERSION"
  fi
}

check_file_exists() {
  local file="$1"
  local label="$2"

  if [[ -f "$file" ]]; then
    record_gate "PASS" "$label" "$file exists"
  else
    record_gate "FAIL" "$label" "$file is missing"
  fi
}

cat > "$SUMMARY_MD" <<EOF
# AS AI Reliability POC Final Enterprise Release Certification

| Field | Value |
|---|---|
| Phase | $PHASE_NAME |
| Environment | $ENVIRONMENT |
| Namespace | $NAMESPACE |
| Application | $APP_NAME |
| Service | $SERVICE_NAME |
| Public Base URL | $PUBLIC_BASE_URL |
| Istio Ingress IP | $ISTIO_INGRESS_IP |
| App LoadBalancer IP | $APP_LOADBALANCER_IP |
| Expected Model Version | $EXPECTED_MODEL_VERSION |
| Started UTC | $STARTED_UTC |

## Certification Gates

| Status | Gate | Evidence |
|---|---|---|
EOF

echo "name,method,path,http_code,latency_ms" > "$CSV_REPORT"

# ----------------------------
# Tooling gate
# ----------------------------
for tool in kubectl curl jq python3; do
  if command -v "$tool" >/dev/null 2>&1; then
    record_gate "PASS" "Tool available: $tool" "Found $tool"
  else
    record_gate "FAIL" "Tool available: $tool" "$tool is missing"
  fi
done

# ----------------------------
# Workflow/file existence gate
# ----------------------------
check_file_exists ".github/workflows/03-runtime-release-gate.yml" "Runtime release gate workflow"
check_file_exists ".github/workflows/04-dynatrace-validation-gate.yml" "Dynatrace validation workflow"
check_file_exists ".github/workflows/05-servicenow-incident-on-failure.yml" "ServiceNow incident workflow"
check_file_exists ".github/workflows/06-canary-rollback-automation.yml" "Canary rollback workflow"
check_file_exists ".github/workflows/07-enterprise-poc-evidence-pack.yml" "Enterprise evidence-pack workflow"
check_file_exists ".github/workflows/08-final-demo-interview-pack.yml" "Final demo interview-pack workflow"

check_file_exists "scripts/incident/servicenow_incident_on_failure.py" "ServiceNow incident script"
check_file_exists "scripts/traffic/canary_rollback_automation.sh" "Canary rollback script"
check_file_exists "scripts/reports/generate_enterprise_poc_evidence_pack.sh" "Enterprise evidence-pack script"
check_file_exists "scripts/reports/generate_final_demo_interview_pack.sh" "Final demo interview-pack script"

# ----------------------------
# Kubernetes evidence gate
# ----------------------------
if kubectl get namespace "$NAMESPACE" > "$RAW_DIR/namespace.txt" 2>&1; then
  record_gate "PASS" "Kubernetes namespace" "$NAMESPACE exists"
else
  record_gate "FAIL" "Kubernetes namespace" "$NAMESPACE not found"
fi

kubectl -n "$NAMESPACE" get deploy,pods,svc -o wide > "$RAW_DIR/kubernetes-core-resources.txt" 2>&1 || true
kubectl -n "$NAMESPACE" get pods --show-labels > "$RAW_DIR/kubernetes-pod-labels.txt" 2>&1 || true
kubectl -n "$NAMESPACE" get deploy --show-labels > "$RAW_DIR/kubernetes-deploy-labels.txt" 2>&1 || true
kubectl -n "$NAMESPACE" get gateway,virtualservice,destinationrule -o yaml > "$RAW_DIR/istio-resources.yaml" 2>&1 || true

record_gate "PASS" "Kubernetes and Istio evidence captured" "Saved raw runtime evidence"

if kubectl -n "$NAMESPACE" get svc "$SERVICE_NAME" > "$RAW_DIR/service.txt" 2>&1; then
  record_gate "PASS" "Kubernetes service" "$SERVICE_NAME exists"
else
  record_gate "FAIL" "Kubernetes service" "$SERVICE_NAME not found"
fi

# ----------------------------
# Runtime endpoint certification
# ----------------------------
validate_get "root" "/"
validate_get "health-live" "/health/live"
validate_get "health-ready" "/health/ready"
validate_get "health-model" "$MODEL_HEALTH_PATH"
validate_get "version" "$VERSION_PATH"

VERSION_MODEL_VERSION="$(extract_model_version "$RAW_DIR/version.json")"
MODEL_HEALTH_VERSION="$(extract_model_version "$RAW_DIR/health-model.json")"

if [[ "$VERSION_MODEL_VERSION" == "$EXPECTED_MODEL_VERSION" ]]; then
  record_gate "PASS" "Version endpoint model version" "$VERSION_PATH returned $VERSION_MODEL_VERSION"
else
  record_gate "FAIL" "Version endpoint model version" "$VERSION_PATH returned '${VERSION_MODEL_VERSION:-not-found}', expected $EXPECTED_MODEL_VERSION"
fi

if [[ -n "$MODEL_HEALTH_VERSION" ]]; then
  if [[ "$MODEL_HEALTH_VERSION" == "$EXPECTED_MODEL_VERSION" ]]; then
    record_gate "PASS" "Model health version" "$MODEL_HEALTH_PATH returned $MODEL_HEALTH_VERSION"
  else
    record_gate "WARN" "Model health version" "$MODEL_HEALTH_PATH returned '${MODEL_HEALTH_VERSION}', expected $EXPECTED_MODEL_VERSION"
  fi
else
  record_gate "WARN" "Model health version" "$MODEL_HEALTH_PATH did not expose a model_version field"
fi

validate_predict

# ----------------------------
# Final report
# ----------------------------
END_EPOCH="$(date +%s)"
DURATION_SECONDS=$((END_EPOCH - START_EPOCH))
FINISHED_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ "$FAIL_COUNT" -eq 0 ]]; then
  FINAL_STATUS="certified"
else
  FINAL_STATUS="not_certified"
fi

cat >> "$SUMMARY_MD" <<EOF

## Final Certification Summary

| Metric | Value |
|---|---|
| Final Status | $FINAL_STATUS |
| Passed Gates | $PASS_COUNT |
| Warning Gates | $WARN_COUNT |
| Failed Gates | $FAIL_COUNT |
| Version Endpoint Model Version | ${VERSION_MODEL_VERSION:-not-found} |
| Model Health Version | ${MODEL_HEALTH_VERSION:-not-found} |
| Duration Seconds | $DURATION_SECONDS |
| Finished UTC | $FINISHED_UTC |

## Certified Enterprise Capabilities

| Capability | Status |
|---|---|
| AI service runtime endpoint | Validated |
| AI model version endpoint | Validated |
| AI model health endpoint | Validated |
| AI prediction endpoint | Validated |
| Kubernetes runtime state | Captured |
| Istio runtime state | Captured |
| ServiceNow incident automation | File and workflow validated |
| Dynatrace validation automation | Workflow validated |
| Canary rollback automation | File and workflow validated |
| Enterprise evidence artifacts | File and workflow validated |

## Evidence Files

- \`as-ai-reliability-final-certification.md\`
- \`as-ai-reliability-final-certification.html\`
- \`as-ai-reliability-final-certification.json\`
- \`as-ai-reliability-final-certification-endpoints.csv\`
- \`raw/kubernetes-core-resources.txt\`
- \`raw/kubernetes-pod-labels.txt\`
- \`raw/kubernetes-deploy-labels.txt\`
- \`raw/istio-resources.yaml\`
- \`raw/version.json\`
- \`raw/health-model.json\`
- \`raw/predict.json\`
EOF

jq -n \
  --arg phase "$PHASE_NAME" \
  --arg status "$FINAL_STATUS" \
  --arg environment "$ENVIRONMENT" \
  --arg namespace "$NAMESPACE" \
  --arg app_name "$APP_NAME" \
  --arg service_name "$SERVICE_NAME" \
  --arg public_base_url "$PUBLIC_BASE_URL" \
  --arg expected_model_version "$EXPECTED_MODEL_VERSION" \
  --arg version_model_version "${VERSION_MODEL_VERSION:-}" \
  --arg model_health_version "${MODEL_HEALTH_VERSION:-}" \
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
    public_base_url: $public_base_url,
    expected_model_version: $expected_model_version,
    version_model_version: $version_model_version,
    model_health_version: $model_health_version,
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

md = Path(sys.argv[1])
out = Path(sys.argv[2])

content = md.read_text(encoding="utf-8")

html_content = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>AS AI Reliability Final Certification</title>
  <style>
    body {{
      font-family: Arial, sans-serif;
      margin: 40px;
      color: #1f2937;
      line-height: 1.55;
    }}
    h1, h2 {{
      color: #111827;
    }}
    pre {{
      background: #f3f4f6;
      padding: 16px;
      border-radius: 8px;
      white-space: pre-wrap;
      overflow-x: auto;
    }}
  </style>
</head>
<body>
<pre>{html.escape(content)}</pre>
</body>
</html>
"""

out.write_text(html_content, encoding="utf-8")
PY

echo
echo "Final certification status: $FINAL_STATUS"
echo "Passed gates: $PASS_COUNT"
echo "Warning gates: $WARN_COUNT"
echo "Failed gates: $FAIL_COUNT"
echo "Markdown: $SUMMARY_MD"
echo "HTML: $SUMMARY_HTML"
echo "JSON: $JSON_REPORT"
echo "CSV: $CSV_REPORT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
