#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Phase 5 - Dynatrace Validation Gate
# Purpose:
#   Validate that the AS AI Reliability POC is observable in
#   Dynatrace after Kubernetes deployment and runtime validation.
#
# Enterprise value:
#   This creates release evidence proving that the service is not
#   only deployed, but also visible to observability, incident,
#   RCA, and operational support workflows.
# ============================================================

PHASE_NAME="Phase 5 - Dynatrace Validation Gate"

REPORT_ROOT="${REPORT_ROOT:-reports/dynatrace-validation}"
RAW_DIR="$REPORT_ROOT/raw"
SUMMARY="$REPORT_ROOT/dynatrace-validation-summary.md"
JSON_REPORT="$REPORT_ROOT/dynatrace-validation-report.json"

mkdir -p "$RAW_DIR"

DYNATRACE_ENV_URL="${DYNATRACE_ENV_URL:-}"
DYNATRACE_API_TOKEN="${DYNATRACE_API_TOKEN:-}"

APP_NAME="${APP_NAME:-as-ai-quality-service}"
NAMESPACE="${NAMESPACE:-ai-reliability-poc}"

DYNATRACE_SERVICE_QUERY="${DYNATRACE_SERVICE_QUERY:-$APP_NAME}"
DYNATRACE_LOOKBACK_MINUTES="${DYNATRACE_LOOKBACK_MINUTES:-60}"
DYNATRACE_MIN_SERVICE_ENTITIES="${DYNATRACE_MIN_SERVICE_ENTITIES:-1}"
DYNATRACE_REQUIRE_PROBLEM_FREE="${DYNATRACE_REQUIRE_PROBLEM_FREE:-true}"
DYNATRACE_REQUIRE_METRIC_DATA="${DYNATRACE_REQUIRE_METRIC_DATA:-false}"
DYNATRACE_METRIC_SELECTOR="${DYNATRACE_METRIC_SELECTOR:-builtin:service.requestCount.total}"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
START_EPOCH="$(date +%s)"

DYNATRACE_ENV_URL="${DYNATRACE_ENV_URL%/}"

cat > "$SUMMARY" <<EOF
# AS AI Reliability Dynatrace Validation Report

| Field | Value |
|---|---|
| Phase | $PHASE_NAME |
| App Name | $APP_NAME |
| Kubernetes Namespace | $NAMESPACE |
| Dynatrace Service Query | $DYNATRACE_SERVICE_QUERY |
| Dynatrace Lookback Minutes | $DYNATRACE_LOOKBACK_MINUTES |
| Minimum Expected Service Entities | $DYNATRACE_MIN_SERVICE_ENTITIES |
| Require Problem Free | $DYNATRACE_REQUIRE_PROBLEM_FREE |
| Metric Selector | $DYNATRACE_METRIC_SELECTOR |
| Started UTC | $(date -u +"%Y-%m-%dT%H:%M:%SZ") |

## Gate Results

| Status | Gate | Evidence |
|---|---|---|
EOF

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

urlencode() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=""))
PY
}

dynatrace_get() {
  local name="$1"
  local url="$2"
  local body="$RAW_DIR/${name}.json"
  local code_file="$RAW_DIR/${name}.http_code"

  local http_code
  http_code="$(
    curl -k -sS \
      --connect-timeout 10 \
      --max-time 45 \
      -o "$body" \
      -w "%{http_code}" \
      -H "Authorization: Api-Token ${DYNATRACE_API_TOKEN}" \
      -H "Accept: application/json" \
      "$url" || true
  )"

  echo "$http_code" > "$code_file"
  echo "$http_code"
}

is_success_code() {
  local code="$1"
  [[ "$code" =~ ^2 ]]
}

# ----------------------------
# Tooling preflight
# ----------------------------
for tool in curl jq python3; do
  if command -v "$tool" >/dev/null 2>&1; then
    record_gate "PASS" "Tool available: $tool" "Found $tool on runner"
  else
    record_gate "FAIL" "Tool missing: $tool" "$tool is required for Dynatrace validation"
  fi
done

# ----------------------------
# Required configuration checks
# ----------------------------
if [[ -z "$DYNATRACE_ENV_URL" ]]; then
  record_gate "FAIL" "Dynatrace environment URL configured" "DYNATRACE_ENV_URL is missing"
else
  record_gate "PASS" "Dynatrace environment URL configured" "Dynatrace URL is present"
fi

if [[ -z "$DYNATRACE_API_TOKEN" ]]; then
  record_gate "FAIL" "Dynatrace API token configured" "DYNATRACE_API_TOKEN is missing"
else
  record_gate "PASS" "Dynatrace API token configured" "Dynatrace token is present and masked by GitHub"
fi

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  record_gate "FAIL" "Dynatrace validation preflight" "Required Dynatrace configuration is incomplete"
else
  record_gate "PASS" "Dynatrace validation preflight" "Required Dynatrace configuration is complete"
fi

# Stop API checks when critical config is missing.
if [[ -z "$DYNATRACE_ENV_URL" || -z "$DYNATRACE_API_TOKEN" ]]; then
  FINAL_STATUS="failed"
  END_EPOCH="$(date +%s)"
  DURATION_SECONDS=$((END_EPOCH - START_EPOCH))

  cat >> "$SUMMARY" <<EOF

## Dynatrace Gate Summary

| Metric | Value |
|---|---|
| Final Status | $FINAL_STATUS |
| Passed Gates | $PASS_COUNT |
| Warning Gates | $WARN_COUNT |
| Failed Gates | $FAIL_COUNT |
| Duration Seconds | $DURATION_SECONDS |
| Finished UTC | $(date -u +"%Y-%m-%dT%H:%M:%SZ") |
EOF

  jq -n \
    --arg phase "$PHASE_NAME" \
    --arg status "$FINAL_STATUS" \
    --argjson passed_gates "$PASS_COUNT" \
    --argjson warning_gates "$WARN_COUNT" \
    --argjson failed_gates "$FAIL_COUNT" \
    --argjson duration_seconds "$DURATION_SECONDS" \
    '{
      phase: $phase,
      status: $status,
      passed_gates: $passed_gates,
      warning_gates: $warning_gates,
      failed_gates: $failed_gates,
      duration_seconds: $duration_seconds
    }' > "$JSON_REPORT"

  exit 1
fi

# ----------------------------
# Dynatrace service/entity discovery
# ----------------------------
SERVICE_SELECTOR="type(\"SERVICE\"),entityName.contains(\"${DYNATRACE_SERVICE_QUERY}\")"
ENCODED_SERVICE_SELECTOR="$(urlencode "$SERVICE_SELECTOR")"

ENTITIES_URL="${DYNATRACE_ENV_URL}/api/v2/entities?entitySelector=${ENCODED_SERVICE_SELECTOR}&fields=properties,tags&from=now-${DYNATRACE_LOOKBACK_MINUTES}m&pageSize=50"

ENTITY_HTTP_CODE="$(dynatrace_get service_entities "$ENTITIES_URL")"

if is_success_code "$ENTITY_HTTP_CODE"; then
  record_gate "PASS" "Dynatrace service entity API" "Service entity query returned HTTP $ENTITY_HTTP_CODE"
else
  record_gate "FAIL" "Dynatrace service entity API" "Service entity query returned HTTP $ENTITY_HTTP_CODE"
fi

ENTITY_COUNT="$(jq '.totalCount // (.entities | length) // 0' "$RAW_DIR/service_entities.json" 2>/dev/null || echo 0)"

jq -r '
  .entities[]? |
  [
    (.entityId // "unknown"),
    (.displayName // "unknown")
  ] |
  @tsv
' "$RAW_DIR/service_entities.json" > "$RAW_DIR/service-entities.tsv" 2>/dev/null || true

PRIMARY_ENTITY_ID="$(awk 'NR==1 {print $1}' "$RAW_DIR/service-entities.tsv" 2>/dev/null || true)"
PRIMARY_ENTITY_NAME="$(cut -f2- "$RAW_DIR/service-entities.tsv" 2>/dev/null | head -n 1 || true)"

if [[ "$ENTITY_COUNT" -ge "$DYNATRACE_MIN_SERVICE_ENTITIES" ]]; then
  record_gate "PASS" "Dynatrace service entity discovered" "Found $ENTITY_COUNT service entity record(s)"
else
  record_gate "FAIL" "Dynatrace service entity discovered" "Found $ENTITY_COUNT service entity record(s); expected at least $DYNATRACE_MIN_SERVICE_ENTITIES"
fi

if [[ -n "$PRIMARY_ENTITY_ID" ]]; then
  record_gate "PASS" "Primary Dynatrace entity captured" "$PRIMARY_ENTITY_ID / $PRIMARY_ENTITY_NAME"
else
  record_gate "FAIL" "Primary Dynatrace entity captured" "No primary service entity ID was found"
fi

# ----------------------------
# Dynatrace metrics API access
# ----------------------------
ENCODED_METRIC_SELECTOR="$(urlencode "$DYNATRACE_METRIC_SELECTOR")"
METRICS_URL="${DYNATRACE_ENV_URL}/api/v2/metrics/query?metricSelector=${ENCODED_METRIC_SELECTOR}&from=now-${DYNATRACE_LOOKBACK_MINUTES}m"

METRICS_HTTP_CODE="$(dynatrace_get metrics_query "$METRICS_URL")"

if is_success_code "$METRICS_HTTP_CODE"; then
  record_gate "PASS" "Dynatrace metrics API" "Metrics query returned HTTP $METRICS_HTTP_CODE"
else
  record_gate "FAIL" "Dynatrace metrics API" "Metrics query returned HTTP $METRICS_HTTP_CODE"
fi

METRIC_RESULT_COUNT="$(jq '.result | length // 0' "$RAW_DIR/metrics_query.json" 2>/dev/null || echo 0)"

if [[ "$METRIC_RESULT_COUNT" -gt 0 ]]; then
  record_gate "PASS" "Dynatrace metric data returned" "Metric result count: $METRIC_RESULT_COUNT"
else
  if [[ "$DYNATRACE_REQUIRE_METRIC_DATA" == "true" ]]; then
    record_gate "FAIL" "Dynatrace metric data returned" "No metric data returned and DYNATRACE_REQUIRE_METRIC_DATA=true"
  else
    record_gate "WARN" "Dynatrace metric data returned" "No metric data returned; API access worked, but metric data may need more traffic or a different selector"
  fi
fi

# ----------------------------
# Dynatrace problem check
# ----------------------------
PROBLEM_SELECTOR='status("OPEN")'
ENCODED_PROBLEM_SELECTOR="$(urlencode "$PROBLEM_SELECTOR")"

PROBLEMS_URL="${DYNATRACE_ENV_URL}/api/v2/problems?from=now-${DYNATRACE_LOOKBACK_MINUTES}m&problemSelector=${ENCODED_PROBLEM_SELECTOR}&entitySelector=${ENCODED_SERVICE_SELECTOR}&pageSize=50"

PROBLEMS_HTTP_CODE="$(dynatrace_get open_problems "$PROBLEMS_URL")"

if is_success_code "$PROBLEMS_HTTP_CODE"; then
  record_gate "PASS" "Dynatrace problems API" "Open problems query returned HTTP $PROBLEMS_HTTP_CODE"
else
  record_gate "FAIL" "Dynatrace problems API" "Open problems query returned HTTP $PROBLEMS_HTTP_CODE"
fi

OPEN_PROBLEM_COUNT="$(jq '.totalCount // (.problems | length) // 0' "$RAW_DIR/open_problems.json" 2>/dev/null || echo 0)"

jq -r '
  .problems[]? |
  [
    (.problemId // "unknown"),
    (.displayId // "unknown"),
    (.title // "unknown"),
    (.severityLevel // "unknown"),
    (.status // "unknown")
  ] |
  @tsv
' "$RAW_DIR/open_problems.json" > "$RAW_DIR/open-problems.tsv" 2>/dev/null || true

if [[ "$OPEN_PROBLEM_COUNT" -eq 0 ]]; then
  record_gate "PASS" "Dynatrace open problem check" "No open Dynatrace problems found for the service"
else
  if [[ "$DYNATRACE_REQUIRE_PROBLEM_FREE" == "true" ]]; then
    record_gate "FAIL" "Dynatrace open problem check" "$OPEN_PROBLEM_COUNT open problem(s) found for the service"
  else
    record_gate "WARN" "Dynatrace open problem check" "$OPEN_PROBLEM_COUNT open problem(s) found, but problem-free mode is not required"
  fi
fi

# ----------------------------
# Final report
# ----------------------------
END_EPOCH="$(date +%s)"
DURATION_SECONDS=$((END_EPOCH - START_EPOCH))

if [[ "$FAIL_COUNT" -eq 0 ]]; then
  FINAL_STATUS="passed"
else
  FINAL_STATUS="failed"
fi

cat >> "$SUMMARY" <<EOF

## Dynatrace Gate Summary

| Metric | Value |
|---|---|
| Final Status | $FINAL_STATUS |
| Passed Gates | $PASS_COUNT |
| Warning Gates | $WARN_COUNT |
| Failed Gates | $FAIL_COUNT |
| Service Entity Count | $ENTITY_COUNT |
| Primary Entity ID | ${PRIMARY_ENTITY_ID:-none} |
| Primary Entity Name | ${PRIMARY_ENTITY_NAME:-none} |
| Metric Result Count | $METRIC_RESULT_COUNT |
| Open Problem Count | $OPEN_PROBLEM_COUNT |
| Duration Seconds | $DURATION_SECONDS |
| Finished UTC | $(date -u +"%Y-%m-%dT%H:%M:%SZ") |

## Evidence Files

- \`dynatrace-validation-summary.md\`
- \`dynatrace-validation-report.json\`
- \`raw/service_entities.json\`
- \`raw/service-entities.tsv\`
- \`raw/metrics_query.json\`
- \`raw/open_problems.json\`
- \`raw/open-problems.tsv\`
EOF

jq -n \
  --arg phase "$PHASE_NAME" \
  --arg status "$FINAL_STATUS" \
  --arg app_name "$APP_NAME" \
  --arg namespace "$NAMESPACE" \
  --arg service_query "$DYNATRACE_SERVICE_QUERY" \
  --arg primary_entity_id "${PRIMARY_ENTITY_ID:-}" \
  --arg primary_entity_name "${PRIMARY_ENTITY_NAME:-}" \
  --arg metric_selector "$DYNATRACE_METRIC_SELECTOR" \
  --argjson passed_gates "$PASS_COUNT" \
  --argjson warning_gates "$WARN_COUNT" \
  --argjson failed_gates "$FAIL_COUNT" \
  --argjson entity_count "$ENTITY_COUNT" \
  --argjson metric_result_count "$METRIC_RESULT_COUNT" \
  --argjson open_problem_count "$OPEN_PROBLEM_COUNT" \
  --argjson duration_seconds "$DURATION_SECONDS" \
  '{
    phase: $phase,
    status: $status,
    app_name: $app_name,
    namespace: $namespace,
    service_query: $service_query,
    primary_entity_id: $primary_entity_id,
    primary_entity_name: $primary_entity_name,
    metric_selector: $metric_selector,
    passed_gates: $passed_gates,
    warning_gates: $warning_gates,
    failed_gates: $failed_gates,
    entity_count: $entity_count,
    metric_result_count: $metric_result_count,
    open_problem_count: $open_problem_count,
    duration_seconds: $duration_seconds
  }' > "$JSON_REPORT"

echo
echo "Dynatrace validation status: $FINAL_STATUS"
echo "Summary report: $SUMMARY"
echo "JSON report: $JSON_REPORT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
