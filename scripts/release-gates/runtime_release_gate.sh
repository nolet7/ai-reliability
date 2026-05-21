#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Phase 4 - Runtime Release Gate
# Purpose:
#   Validate that the deployed AS AI Reliability POC is healthy
#   after Kubernetes deployment.
#
# Enterprise value:
#   This creates auditable release evidence for SRE, platform,
#   incident, model, and change-management reviews.
# ============================================================

PHASE_NAME="Phase 4 - Runtime Release Gate"

REPORT_ROOT="${REPORT_ROOT:-reports/runtime-release-gate}"
RAW_DIR="$REPORT_ROOT/raw"
SUMMARY="$REPORT_ROOT/runtime-release-gate-summary.md"
JSON_REPORT="$REPORT_ROOT/runtime-release-gate-report.json"
CSV_REPORT="$REPORT_ROOT/runtime-release-gate-samples.csv"
LATENCY_FILE="$RAW_DIR/predict-latencies-ms.txt"

mkdir -p "$RAW_DIR"
: > "$CSV_REPORT"
: > "$LATENCY_FILE"

NAMESPACE="${NAMESPACE:-ai-reliability-poc}"
APP_NAME="${APP_NAME:-as-ai-quality-service}"
EXPECTED_MODEL_VERSION="${EXPECTED_MODEL_VERSION:-v1.0.3}"

ISTIO_INGRESS_IP="${ISTIO_INGRESS_IP:-139.144.255.92}"
APP_LOADBALANCER_IP="${APP_LOADBALANCER_IP:-139.144.255.192}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-}"

HEALTH_PATH="${HEALTH_PATH:-/health}"
MODEL_PATH="${MODEL_PATH:-/model}"
PREDICT_PATH="${PREDICT_PATH:-/predict}"

RUNTIME_GATE_REQUESTS="${RUNTIME_GATE_REQUESTS:-30}"
RUNTIME_GATE_MAX_FAILURES="${RUNTIME_GATE_MAX_FAILURES:-0}"
RUNTIME_GATE_MAX_P95_MS="${RUNTIME_GATE_MAX_P95_MS:-1000}"

# Default prediction payload.
# If your /predict endpoint uses a different request schema,
# override this with GitHub variable PREDICT_PAYLOAD.
PREDICT_PAYLOAD="${PREDICT_PAYLOAD:-{\"site_id\":\"asr-poc-site-01\",\"asset_id\":\"quality-line-01\",\"features\":{\"temperature\":72.3,\"vibration\":0.12,\"pressure\":3.4,\"humidity\":45.0}}}"

START_EPOCH="$(date +%s)"
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

if [[ -n "$PUBLIC_BASE_URL" ]]; then
  BASE_URL="$PUBLIC_BASE_URL"
elif [[ -n "$ISTIO_INGRESS_IP" ]]; then
  BASE_URL="http://$ISTIO_INGRESS_IP"
else
  BASE_URL="http://$APP_LOADBALANCER_IP"
fi

BASE_URL="${BASE_URL%/}"

cat > "$SUMMARY" <<EOF
# AS AI Reliability Runtime Release Gate Report

| Field | Value |
|---|---|
| Phase | $PHASE_NAME |
| Namespace | $NAMESPACE |
| App Name | $APP_NAME |
| Base URL | $BASE_URL |
| Expected Model Version | $EXPECTED_MODEL_VERSION |
| Request Count | $RUNTIME_GATE_REQUESTS |
| Max Allowed Runtime Failures | $RUNTIME_GATE_MAX_FAILURES |
| Max Allowed Predict p95 Latency | ${RUNTIME_GATE_MAX_P95_MS}ms |
| Started UTC | $(date -u +"%Y-%m-%dT%H:%M:%SZ") |

## Gate Results

| Status | Gate | Evidence |
|---|---|---|
EOF

echo "sample,type,http_code,model_version,latency_ms" > "$CSV_REPORT"

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

http_get() {
  local name="$1"
  local path="$2"
  local output="$RAW_DIR/${name}.json"

  curl -k -sS \
    --connect-timeout 5 \
    --max-time 20 \
    -o "$output" \
    -w "%{http_code}" \
    "$BASE_URL$path" || true
}

http_post_predict() {
  local sample="$1"
  local output="$RAW_DIR/predict_${sample}.json"

  curl -k -sS \
    --connect-timeout 5 \
    --max-time 30 \
    -o "$output" \
    -w "%{http_code},%{time_total}" \
    -X POST "$BASE_URL$PREDICT_PATH" \
    -H "Content-Type: application/json" \
    -d "$PREDICT_PAYLOAD" || true
}

http_get_model_sample() {
  local sample="$1"
  local output="$RAW_DIR/model_${sample}.json"

  curl -k -sS \
    --connect-timeout 5 \
    --max-time 20 \
    -o "$output" \
    -w "%{http_code},%{time_total}" \
    "$BASE_URL$MODEL_PATH" || true
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
    empty
  ' "$file" 2>/dev/null | head -n 1
}

# ----------------------------
# Tooling preflight
# ----------------------------
for tool in kubectl curl jq python3; do
  if command -v "$tool" >/dev/null 2>&1; then
    record_gate "PASS" "Tool available: $tool" "Found $tool on runner"
  else
    record_gate "FAIL" "Tool missing: $tool" "$tool is required for runtime validation"
  fi
done

# ----------------------------
# Kubernetes runtime evidence
# ----------------------------
if kubectl config current-context > "$RAW_DIR/kube-current-context.txt" 2>&1; then
  record_gate "PASS" "Kube context available" "Saved to raw/kube-current-context.txt"
else
  record_gate "FAIL" "Kube context unavailable" "Unable to read kube context"
fi

if kubectl get namespace "$NAMESPACE" > "$RAW_DIR/namespace.txt" 2>&1; then
  record_gate "PASS" "Namespace exists" "$NAMESPACE"
else
  record_gate "FAIL" "Namespace missing" "$NAMESPACE"
fi

kubectl -n "$NAMESPACE" get deploy,svc,pods -o wide > "$RAW_DIR/kubernetes-core-resources.txt" 2>&1 || true
kubectl -n "$NAMESPACE" get virtualservice,destinationrule,gateway -o wide > "$RAW_DIR/istio-runtime-resources.txt" 2>&1 || true

record_gate "PASS" "Runtime resource evidence captured" "Saved Kubernetes and Istio resource snapshots"

# Find deployments by app label first.
mapfile -t DEPLOYS < <(
  kubectl -n "$NAMESPACE" get deploy -l "app=$APP_NAME" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
)

# Fallback for Helm-style labels.
if [[ "${#DEPLOYS[@]}" -eq 0 ]]; then
  mapfile -t DEPLOYS < <(
    kubectl -n "$NAMESPACE" get deploy -l "app.kubernetes.io/name=$APP_NAME" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
  )
fi

# Final fallback: deployment name equals APP_NAME.
if [[ "${#DEPLOYS[@]}" -eq 0 ]]; then
  if kubectl -n "$NAMESPACE" get deploy "$APP_NAME" >/dev/null 2>&1; then
    DEPLOYS=("$APP_NAME")
  fi
fi

if [[ "${#DEPLOYS[@]}" -eq 0 ]]; then
  record_gate "FAIL" "Deployment discovery" "No deployment found for $APP_NAME"
else
  record_gate "PASS" "Deployment discovery" "Found deployments: ${DEPLOYS[*]}"

  for deploy in "${DEPLOYS[@]}"; do
    if kubectl -n "$NAMESPACE" rollout status "deployment/$deploy" --timeout=180s > "$RAW_DIR/rollout-${deploy}.txt" 2>&1; then
      record_gate "PASS" "Rollout status: $deploy" "Deployment rollout completed"
    else
      record_gate "FAIL" "Rollout status: $deploy" "Deployment rollout failed or timed out"
    fi
  done
fi

if kubectl -n "$NAMESPACE" wait --for=condition=Ready pod -l "app=$APP_NAME" --timeout=180s > "$RAW_DIR/pod-readiness.txt" 2>&1; then
  record_gate "PASS" "Pod readiness" "Pods with label app=$APP_NAME are Ready"
else
  if kubectl -n "$NAMESPACE" wait --for=condition=Ready pod -l "app.kubernetes.io/name=$APP_NAME" --timeout=180s >> "$RAW_DIR/pod-readiness.txt" 2>&1; then
    record_gate "PASS" "Pod readiness" "Pods with Helm-style app label are Ready"
  else
    record_gate "WARN" "Pod readiness label check" "Readiness check by expected labels did not fully match; review raw/pod-readiness.txt"
  fi
fi

# ----------------------------
# HTTP health endpoint gate
# ----------------------------
HEALTH_CODE="$(http_get health "$HEALTH_PATH")"

if [[ "$HEALTH_CODE" =~ ^2 ]]; then
  record_gate "PASS" "HTTP health endpoint" "$HEALTH_PATH returned HTTP $HEALTH_CODE"
else
  record_gate "FAIL" "HTTP health endpoint" "$HEALTH_PATH returned HTTP $HEALTH_CODE"
fi

# ----------------------------
# Model endpoint version gate
# ----------------------------
MODEL_FAILURES=0
MODEL_UNEXPECTED=0

for i in $(seq 1 "$RUNTIME_GATE_REQUESTS"); do
  metrics="$(http_get_model_sample "$i")"
  code="${metrics%%,*}"
  seconds="${metrics#*,}"
  latency_ms="$(seconds_to_ms "$seconds")"
  model_file="$RAW_DIR/model_${i}.json"
  model_version="$(extract_model_version "$model_file")"

  echo "$i,model,$code,$model_version,$latency_ms" >> "$CSV_REPORT"

  if [[ ! "$code" =~ ^2 ]]; then
    MODEL_FAILURES=$((MODEL_FAILURES + 1))
  fi

  if [[ "$model_version" != "$EXPECTED_MODEL_VERSION" ]]; then
    MODEL_UNEXPECTED=$((MODEL_UNEXPECTED + 1))
  fi
done

if [[ "$MODEL_FAILURES" -le "$RUNTIME_GATE_MAX_FAILURES" ]]; then
  record_gate "PASS" "Model endpoint availability" "$MODEL_FAILURES failures out of $RUNTIME_GATE_REQUESTS"
else
  record_gate "FAIL" "Model endpoint availability" "$MODEL_FAILURES failures out of $RUNTIME_GATE_REQUESTS"
fi

if [[ "$MODEL_UNEXPECTED" -eq 0 ]]; then
  record_gate "PASS" "Model version correctness" "All model responses matched $EXPECTED_MODEL_VERSION"
else
  record_gate "FAIL" "Model version correctness" "$MODEL_UNEXPECTED responses did not match $EXPECTED_MODEL_VERSION"
fi

# ----------------------------
# Predict endpoint gate
# ----------------------------
PREDICT_FAILURES=0

for i in $(seq 1 "$RUNTIME_GATE_REQUESTS"); do
  metrics="$(http_post_predict "$i")"
  code="${metrics%%,*}"
  seconds="${metrics#*,}"
  latency_ms="$(seconds_to_ms "$seconds")"

  echo "$latency_ms" >> "$LATENCY_FILE"
  echo "$i,predict,$code,,${latency_ms}" >> "$CSV_REPORT"

  if [[ ! "$code" =~ ^2 ]]; then
    PREDICT_FAILURES=$((PREDICT_FAILURES + 1))
  fi
done

P95_MS="$(python3 - "$LATENCY_FILE" <<'PY'
import sys, math

path = sys.argv[1]
values = []

try:
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                values.append(int(float(line)))
except Exception:
    values = []

if not values:
    print(0)
else:
    values.sort()
    index = max(0, math.ceil(len(values) * 0.95) - 1)
    print(values[index])
PY
)"

if [[ "$PREDICT_FAILURES" -le "$RUNTIME_GATE_MAX_FAILURES" ]]; then
  record_gate "PASS" "Predict endpoint availability" "$PREDICT_FAILURES failures out of $RUNTIME_GATE_REQUESTS"
else
  record_gate "FAIL" "Predict endpoint availability" "$PREDICT_FAILURES failures out of $RUNTIME_GATE_REQUESTS"
fi

if [[ "$P95_MS" -le "$RUNTIME_GATE_MAX_P95_MS" ]]; then
  record_gate "PASS" "Predict latency p95" "${P95_MS}ms <= ${RUNTIME_GATE_MAX_P95_MS}ms"
else
  record_gate "FAIL" "Predict latency p95" "${P95_MS}ms > ${RUNTIME_GATE_MAX_P95_MS}ms"
fi

END_EPOCH="$(date +%s)"
DURATION_SECONDS=$((END_EPOCH - START_EPOCH))

if [[ "$FAIL_COUNT" -eq 0 ]]; then
  FINAL_STATUS="passed"
else
  FINAL_STATUS="failed"
fi

cat >> "$SUMMARY" <<EOF

## Runtime Gate Summary

| Metric | Value |
|---|---|
| Final Status | $FINAL_STATUS |
| Passed Gates | $PASS_COUNT |
| Warning Gates | $WARN_COUNT |
| Failed Gates | $FAIL_COUNT |
| Model Endpoint Failures | $MODEL_FAILURES |
| Unexpected Model Versions | $MODEL_UNEXPECTED |
| Predict Endpoint Failures | $PREDICT_FAILURES |
| Predict p95 Latency | ${P95_MS}ms |
| Duration Seconds | $DURATION_SECONDS |
| Finished UTC | $(date -u +"%Y-%m-%dT%H:%M:%SZ") |

## Evidence Files

- \`runtime-release-gate-summary.md\`
- \`runtime-release-gate-report.json\`
- \`runtime-release-gate-samples.csv\`
- \`raw/\`
EOF

jq -n \
  --arg phase "$PHASE_NAME" \
  --arg status "$FINAL_STATUS" \
  --arg namespace "$NAMESPACE" \
  --arg app_name "$APP_NAME" \
  --arg base_url "$BASE_URL" \
  --arg expected_model_version "$EXPECTED_MODEL_VERSION" \
  --argjson passed_gates "$PASS_COUNT" \
  --argjson warning_gates "$WARN_COUNT" \
  --argjson failed_gates "$FAIL_COUNT" \
  --argjson runtime_requests "$RUNTIME_GATE_REQUESTS" \
  --argjson model_failures "$MODEL_FAILURES" \
  --argjson unexpected_model_versions "$MODEL_UNEXPECTED" \
  --argjson predict_failures "$PREDICT_FAILURES" \
  --argjson predict_p95_ms "$P95_MS" \
  --argjson max_p95_ms "$RUNTIME_GATE_MAX_P95_MS" \
  --argjson duration_seconds "$DURATION_SECONDS" \
  '{
    phase: $phase,
    status: $status,
    namespace: $namespace,
    app_name: $app_name,
    base_url: $base_url,
    expected_model_version: $expected_model_version,
    passed_gates: $passed_gates,
    warning_gates: $warning_gates,
    failed_gates: $failed_gates,
    runtime_requests: $runtime_requests,
    model_failures: $model_failures,
    unexpected_model_versions: $unexpected_model_versions,
    predict_failures: $predict_failures,
    predict_p95_ms: $predict_p95_ms,
    max_p95_ms: $max_p95_ms,
    duration_seconds: $duration_seconds
  }' > "$JSON_REPORT"

echo
echo "Runtime release gate status: $FINAL_STATUS"
echo "Summary report: $SUMMARY"
echo "JSON report: $JSON_REPORT"
echo "CSV samples: $CSV_REPORT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
