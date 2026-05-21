#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Phase 7 - Canary / Rollback Automation
#
# Purpose:
#   Automate Istio traffic shifting for AS AI Reliability POC.
#
# Modes:
#   canary   -> split traffic between v1 and v2
#   rollback -> route 100% traffic to v1
#   promote  -> route 100% traffic to v2
#
# Enterprise value:
#   Creates auditable release evidence for progressive delivery,
#   controlled rollback, SRE release gates, and incident response.
# ============================================================

PHASE_NAME="Phase 7 - Canary / Rollback Automation"

REPORT_ROOT="${REPORT_ROOT:-reports/canary-rollback}"
RAW_DIR="$REPORT_ROOT/raw"
SUMMARY="$REPORT_ROOT/canary-rollback-summary.md"
JSON_REPORT="$REPORT_ROOT/canary-rollback-report.json"
CSV_REPORT="$REPORT_ROOT/canary-rollback-samples.csv"

mkdir -p "$RAW_DIR"

MODE="${MODE:-canary}"

NAMESPACE="${NAMESPACE:-ai-reliability-poc}"
APP_NAME="${APP_NAME:-as-ai-quality-service}"
SERVICE_NAME="${SERVICE_NAME:-$APP_NAME}"

ISTIO_GATEWAY_NAME="${ISTIO_GATEWAY_NAME:-${APP_NAME}-gateway}"
ISTIO_VIRTUAL_SERVICE_NAME="${ISTIO_VIRTUAL_SERVICE_NAME:-${APP_NAME}}"
ISTIO_DESTINATION_RULE_NAME="${ISTIO_DESTINATION_RULE_NAME:-${APP_NAME}}"

ISTIO_INGRESS_IP="${ISTIO_INGRESS_IP:-139.144.255.92}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-http://${ISTIO_INGRESS_IP}}"

ROUTE_TEST_PATH="${ROUTE_TEST_PATH:-/version}"
MODEL_HEALTH_PATH="${MODEL_HEALTH_PATH:-/health/model}"
VALIDATION_REQUESTS="${VALIDATION_REQUESTS:-30}"
EXPECTED_PRIMARY_MODEL_VERSION="${EXPECTED_PRIMARY_MODEL_VERSION:-v1.0.3}"

CANARY_V1_WEIGHT="${CANARY_V1_WEIGHT:-80}"
CANARY_V2_WEIGHT="${CANARY_V2_WEIGHT:-20}"

ROLLBACK_V1_WEIGHT="${ROLLBACK_V1_WEIGHT:-100}"
ROLLBACK_V2_WEIGHT="${ROLLBACK_V2_WEIGHT:-0}"

PROMOTE_V1_WEIGHT="${PROMOTE_V1_WEIGHT:-0}"
PROMOTE_V2_WEIGHT="${PROMOTE_V2_WEIGHT:-100}"

CANARY_TOLERANCE_PERCENT="${CANARY_TOLERANCE_PERCENT:-35}"

BASE_URL="${PUBLIC_BASE_URL%/}"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
START_EPOCH="$(date +%s)"

record_gate() {
  local status="$1"
  local gate="$2"
  local evidence="$3"

  echo "| $status | $gate | $evidence |" >> "$SUMMARY"

  case "$status" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
  esac
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

seconds_to_ms() {
  python3 - "$1" <<'PY'
import sys
try:
    print(int(float(sys.argv[1]) * 1000))
except Exception:
    print(0)
PY
}

case "$MODE" in
  canary)
    V1_WEIGHT="$CANARY_V1_WEIGHT"
    V2_WEIGHT="$CANARY_V2_WEIGHT"
    ;;
  rollback)
    V1_WEIGHT="$ROLLBACK_V1_WEIGHT"
    V2_WEIGHT="$ROLLBACK_V2_WEIGHT"
    ;;
  promote)
    V1_WEIGHT="$PROMOTE_V1_WEIGHT"
    V2_WEIGHT="$PROMOTE_V2_WEIGHT"
    ;;
  *)
    echo "Invalid MODE=$MODE. Allowed values: canary, rollback, promote"
    exit 1
    ;;
esac

cat > "$SUMMARY" <<EOF
# AS AI Reliability Canary / Rollback Automation Report

| Field | Value |
|---|---|
| Phase | $PHASE_NAME |
| Mode | $MODE |
| Namespace | $NAMESPACE |
| App Name | $APP_NAME |
| Service Name | $SERVICE_NAME |
| VirtualService | $ISTIO_VIRTUAL_SERVICE_NAME |
| DestinationRule | $ISTIO_DESTINATION_RULE_NAME |
| Gateway | $ISTIO_GATEWAY_NAME |
| Base URL | $BASE_URL |
| Route Test Path | $ROUTE_TEST_PATH |
| Model Health Path | $MODEL_HEALTH_PATH |
| v1 Weight | $V1_WEIGHT |
| v2 Weight | $V2_WEIGHT |
| Validation Requests | $VALIDATION_REQUESTS |
| Expected Primary Model Version | $EXPECTED_PRIMARY_MODEL_VERSION |
| Started UTC | $(date -u +"%Y-%m-%dT%H:%M:%SZ") |

## Gate Results

| Status | Gate | Evidence |
|---|---|---|
EOF

echo "sample,http_code,model_version,latency_ms" > "$CSV_REPORT"

# ----------------------------
# Tooling preflight
# ----------------------------
for tool in kubectl curl jq python3; do
  if command -v "$tool" >/dev/null 2>&1; then
    record_gate "PASS" "Tool available: $tool" "Found $tool on runner"
  else
    record_gate "FAIL" "Tool missing: $tool" "$tool is required"
  fi
done

# ----------------------------
# Kubernetes / Istio preflight
# ----------------------------
if kubectl get namespace "$NAMESPACE" > "$RAW_DIR/namespace.txt" 2>&1; then
  record_gate "PASS" "Namespace exists" "$NAMESPACE"
else
  record_gate "FAIL" "Namespace exists" "$NAMESPACE was not found"
fi

kubectl -n "$NAMESPACE" get pods,svc,deploy -o wide > "$RAW_DIR/kubernetes-before-route.txt" 2>&1 || true
kubectl -n "$NAMESPACE" get gateway,virtualservice,destinationrule -o yaml > "$RAW_DIR/istio-before-route.yaml" 2>&1 || true

if kubectl -n "$NAMESPACE" get svc "$SERVICE_NAME" > "$RAW_DIR/service.txt" 2>&1; then
  record_gate "PASS" "Kubernetes service exists" "$SERVICE_NAME"
else
  record_gate "FAIL" "Kubernetes service exists" "$SERVICE_NAME was not found"
fi

# ----------------------------
# Apply DestinationRule and VirtualService
# ----------------------------
cat > "$RAW_DIR/istio-canary-rollback-route.yaml" <<EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: ${ISTIO_DESTINATION_RULE_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    managed-by: github-actions
    phase: canary-rollback
spec:
  host: ${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: ${ISTIO_VIRTUAL_SERVICE_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    managed-by: github-actions
    phase: canary-rollback
spec:
  hosts:
    - "*"
  gateways:
    - ${ISTIO_GATEWAY_NAME}
  http:
    - name: ${MODE}-route
      route:
        - destination:
            host: ${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local
            subset: v1
          weight: ${V1_WEIGHT}
        - destination:
            host: ${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local
            subset: v2
          weight: ${V2_WEIGHT}
EOF

if kubectl apply -f "$RAW_DIR/istio-canary-rollback-route.yaml" > "$RAW_DIR/apply-route.txt" 2>&1; then
  record_gate "PASS" "Istio route applied" "Applied $MODE route: v1=$V1_WEIGHT v2=$V2_WEIGHT"
else
  record_gate "FAIL" "Istio route applied" "Failed to apply Istio route"
fi

sleep 10

kubectl -n "$NAMESPACE" get virtualservice "$ISTIO_VIRTUAL_SERVICE_NAME" -o yaml > "$RAW_DIR/virtualservice-after-route.yaml" 2>&1 || true
kubectl -n "$NAMESPACE" get destinationrule "$ISTIO_DESTINATION_RULE_NAME" -o yaml > "$RAW_DIR/destinationrule-after-route.yaml" 2>&1 || true

# ----------------------------
# Validate route behavior
# ----------------------------
HTTP_FAILURES=0
V1_COUNT=0
V2_OR_OTHER_COUNT=0
PRIMARY_VERSION_COUNT=0

for i in $(seq 1 "$VALIDATION_REQUESTS"); do
  output_file="$RAW_DIR/route_sample_${i}.json"

  metrics="$(
    curl -k -sS \
      --connect-timeout 5 \
      --max-time 20 \
      -o "$output_file" \
      -w "%{http_code},%{time_total}" \
      "$BASE_URL$ROUTE_TEST_PATH" || true
  )"

  http_code="${metrics%%,*}"
  seconds="${metrics#*,}"
  latency_ms="$(seconds_to_ms "$seconds")"
  model_version="$(extract_model_version "$output_file")"

  echo "$i,$http_code,$model_version,$latency_ms" >> "$CSV_REPORT"

  if [[ ! "$http_code" =~ ^2 ]]; then
    HTTP_FAILURES=$((HTTP_FAILURES + 1))
  fi

  if [[ "$model_version" == "$EXPECTED_PRIMARY_MODEL_VERSION" ]]; then
    PRIMARY_VERSION_COUNT=$((PRIMARY_VERSION_COUNT + 1))
    V1_COUNT=$((V1_COUNT + 1))
  else
    V2_OR_OTHER_COUNT=$((V2_OR_OTHER_COUNT + 1))
  fi
done

if [[ "$HTTP_FAILURES" -eq 0 ]]; then
  record_gate "PASS" "Route HTTP validation" "0 HTTP failures out of $VALIDATION_REQUESTS"
else
  record_gate "FAIL" "Route HTTP validation" "$HTTP_FAILURES HTTP failures out of $VALIDATION_REQUESTS"
fi

MODEL_HEALTH_OUTPUT="$RAW_DIR/model-health.json"
MODEL_HEALTH_CODE="$(
  curl -k -sS \
    --connect-timeout 5 \
    --max-time 20 \
    -o "$MODEL_HEALTH_OUTPUT" \
    -w "%{http_code}" \
    "$BASE_URL$MODEL_HEALTH_PATH" || true
)"

MODEL_HEALTH_VERSION="$(extract_model_version "$MODEL_HEALTH_OUTPUT")"

if [[ "$MODEL_HEALTH_CODE" =~ ^2 ]]; then
  record_gate "PASS" "AI model health endpoint" "$MODEL_HEALTH_PATH returned HTTP $MODEL_HEALTH_CODE"
else
  record_gate "FAIL" "AI model health endpoint" "$MODEL_HEALTH_PATH returned HTTP $MODEL_HEALTH_CODE"
fi

if [[ "$MODEL_HEALTH_VERSION" == "$EXPECTED_PRIMARY_MODEL_VERSION" ]]; then
  record_gate "PASS" "AI model version health" "$MODEL_HEALTH_PATH returned expected model version $EXPECTED_PRIMARY_MODEL_VERSION"
else
  record_gate "WARN" "AI model version health" "$MODEL_HEALTH_PATH returned model version '${MODEL_HEALTH_VERSION:-not-found}'; rollback validation still uses $ROUTE_TEST_PATH"
fi

if [[ "$MODE" == "rollback" ]]; then
  if [[ "$PRIMARY_VERSION_COUNT" -eq "$VALIDATION_REQUESTS" ]]; then
    record_gate "PASS" "Rollback validation" "$PRIMARY_VERSION_COUNT/$VALIDATION_REQUESTS requests returned $EXPECTED_PRIMARY_MODEL_VERSION"
  else
    record_gate "FAIL" "Rollback validation" "$PRIMARY_VERSION_COUNT/$VALIDATION_REQUESTS requests returned $EXPECTED_PRIMARY_MODEL_VERSION"
  fi
fi

if [[ "$MODE" == "canary" ]]; then
  EXPECTED_V2="$V2_WEIGHT"

  ACTUAL_V2_PERCENT="$(
    python3 - "$V2_OR_OTHER_COUNT" "$VALIDATION_REQUESTS" <<'PY'
import sys
v2 = int(sys.argv[1])
total = int(sys.argv[2])
print(round((v2 / total) * 100, 2) if total else 0)
PY
  )"

  LOWER_BOUND="$(
    python3 - "$EXPECTED_V2" "$CANARY_TOLERANCE_PERCENT" <<'PY'
import sys
expected = float(sys.argv[1])
tol = float(sys.argv[2])
print(max(0, expected - tol))
PY
  )"

  UPPER_BOUND="$(
    python3 - "$EXPECTED_V2" "$CANARY_TOLERANCE_PERCENT" <<'PY'
import sys
expected = float(sys.argv[1])
tol = float(sys.argv[2])
print(min(100, expected + tol))
PY
  )"

  WITHIN_RANGE="$(
    python3 - "$ACTUAL_V2_PERCENT" "$LOWER_BOUND" "$UPPER_BOUND" <<'PY'
import sys
actual = float(sys.argv[1])
low = float(sys.argv[2])
high = float(sys.argv[3])
print("true" if low <= actual <= high else "false")
PY
  )"

  if [[ "$WITHIN_RANGE" == "true" ]]; then
    record_gate "PASS" "Canary distribution validation" "v2/other observed ${ACTUAL_V2_PERCENT}% within tolerance range ${LOWER_BOUND}-${UPPER_BOUND}%"
  else
    record_gate "WARN" "Canary distribution validation" "v2/other observed ${ACTUAL_V2_PERCENT}% outside tolerance range ${LOWER_BOUND}-${UPPER_BOUND}%; small sample size can affect this"
  fi
fi

if [[ "$MODE" == "promote" ]]; then
  if [[ "$V2_OR_OTHER_COUNT" -eq "$VALIDATION_REQUESTS" ]]; then
    record_gate "PASS" "Promotion validation" "$V2_OR_OTHER_COUNT/$VALIDATION_REQUESTS requests routed away from primary version"
  else
    record_gate "WARN" "Promotion validation" "$V2_OR_OTHER_COUNT/$VALIDATION_REQUESTS requests routed away from primary version; confirm v2 response schema/version"
  fi
fi

END_EPOCH="$(date +%s)"
DURATION_SECONDS=$((END_EPOCH - START_EPOCH))

if [[ "$FAIL_COUNT" -eq 0 ]]; then
  FINAL_STATUS="passed"
else
  FINAL_STATUS="failed"
fi

cat >> "$SUMMARY" <<EOF

## Canary / Rollback Summary

| Metric | Value |
|---|---|
| Final Status | $FINAL_STATUS |
| Mode | $MODE |
| Passed Gates | $PASS_COUNT |
| Warning Gates | $WARN_COUNT |
| Failed Gates | $FAIL_COUNT |
| HTTP Failures | $HTTP_FAILURES |
| Primary Version Count | $PRIMARY_VERSION_COUNT |
| Non-primary / v2-or-other Count | $V2_OR_OTHER_COUNT |
| Duration Seconds | $DURATION_SECONDS |
| Finished UTC | $(date -u +"%Y-%m-%dT%H:%M:%SZ") |

## Evidence Files

- \`canary-rollback-summary.md\`
- \`canary-rollback-report.json\`
- \`canary-rollback-samples.csv\`
- \`raw/istio-canary-rollback-route.yaml\`
- \`raw/virtualservice-after-route.yaml\`
- \`raw/destinationrule-after-route.yaml\`
- \`raw/kubernetes-before-route.txt\`
EOF

jq -n \
  --arg phase "$PHASE_NAME" \
  --arg status "$FINAL_STATUS" \
  --arg mode "$MODE" \
  --arg namespace "$NAMESPACE" \
  --arg app_name "$APP_NAME" \
  --arg service_name "$SERVICE_NAME" \
  --arg base_url "$BASE_URL" \
  --arg route_test_path "$ROUTE_TEST_PATH" \
  --arg expected_primary_model_version "$EXPECTED_PRIMARY_MODEL_VERSION" \
  --argjson v1_weight "$V1_WEIGHT" \
  --argjson v2_weight "$V2_WEIGHT" \
  --argjson validation_requests "$VALIDATION_REQUESTS" \
  --argjson passed_gates "$PASS_COUNT" \
  --argjson warning_gates "$WARN_COUNT" \
  --argjson failed_gates "$FAIL_COUNT" \
  --argjson http_failures "$HTTP_FAILURES" \
  --argjson primary_version_count "$PRIMARY_VERSION_COUNT" \
  --argjson v2_or_other_count "$V2_OR_OTHER_COUNT" \
  --argjson duration_seconds "$DURATION_SECONDS" \
  '{
    phase: $phase,
    status: $status,
    mode: $mode,
    namespace: $namespace,
    app_name: $app_name,
    service_name: $service_name,
    base_url: $base_url,
    route_test_path: $route_test_path,
    expected_primary_model_version: $expected_primary_model_version,
    v1_weight: $v1_weight,
    v2_weight: $v2_weight,
    validation_requests: $validation_requests,
    passed_gates: $passed_gates,
    warning_gates: $warning_gates,
    failed_gates: $failed_gates,
    http_failures: $http_failures,
    primary_version_count: $primary_version_count,
    v2_or_other_count: $v2_or_other_count,
    duration_seconds: $duration_seconds
  }' > "$JSON_REPORT"

echo
echo "Canary / rollback automation status: $FINAL_STATUS"
echo "Mode: $MODE"
echo "Route: v1=$V1_WEIGHT v2=$V2_WEIGHT"
echo "Summary report: $SUMMARY"
echo "JSON report: $JSON_REPORT"
echo "CSV report: $CSV_REPORT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
