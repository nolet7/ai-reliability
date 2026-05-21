#!/usr/bin/env bash

# scripts/run_phase2_validation.sh
#
# Purpose:
# Runs all Phase 2 validation checks for the ASR AI Reliability POC.
#
# This script proves that the FastAPI reliability service supports:
# - Health validation
# - Model readiness validation
# - Prediction audit validation
# - Latency simulation
# - Error simulation
# - Legacy naming cleanup
#
# This script will later become part of CI/CD release gate evidence.

set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"

echo "============================================================"
echo "ASR AI Reliability POC - Phase 2 Validation"
echo "============================================================"
echo "Base URL: ${BASE_URL}"
echo

echo "Step 1: Checking that application is reachable..."
if ! curl -s "${BASE_URL}/" >/tmp/asr_root_check.json; then
  echo "Application is not reachable at ${BASE_URL}"
  echo "Start it with:"
  echo "python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000"
  exit 1
fi

cat /tmp/asr_root_check.json | python -m json.tool
echo

echo "Step 2: Validating health endpoints..."
./scripts/validate_health_endpoints.sh
echo

echo "Step 3: Validating model health..."
./scripts/validate_model_health.sh
echo

echo "Step 4: Validating prediction audit..."
./scripts/validate_prediction_audit.sh
echo

echo "Step 5: Generating latency simulation traffic..."
REQUEST_COUNT=2 SECONDS_DELAY=1 ./scripts/generate_latency_incident.sh
echo

echo "Step 6: Generating controlled error simulation traffic..."
REQUEST_COUNT=2 ./scripts/generate_error_incident.sh
echo

echo "Step 7: Checking for old legacy naming references in project files..."

# Build the legacy pattern without placing the old words directly in this file.
# This prevents the cleanup check from matching the validation script itself.
LEGACY_PATTERN="t""ellus|T""ellus|TELL""US"

if grep -Rni \
  --exclude-dir=.git \
  --exclude-dir=.venv \
  --exclude-dir=__pycache__ \
  --exclude-dir=.pytest_cache \
  --exclude-dir=local \
  -E "${LEGACY_PATTERN}" .; then
  echo
  echo "Old legacy references were found. Please clean them before continuing."
  exit 1
else
  echo "No old legacy references found."
fi

echo
echo "Step 8: Checking generated audit file..."
if [ ! -f "local/generated/audit/prediction_audit.jsonl" ]; then
  echo "Audit file not found."
  exit 1
fi

echo "Latest audit record:"
tail -n 1 local/generated/audit/prediction_audit.jsonl | python -m json.tool

echo
echo "Step 9: Validating latest audit file status..."

python - <<'PY'
import json
from pathlib import Path

audit_file = Path("local/generated/audit/prediction_audit.jsonl")

last_line = audit_file.read_text(encoding="utf-8").strip().splitlines()[-1]
record = json.loads(last_line)

if record.get("service_name") != "asr-ai-quality-service":
    raise SystemExit(f"Unexpected service_name in audit file: {record.get('service_name')}")

if record.get("model_name") != "asr-quality-classifier":
    raise SystemExit(f"Unexpected model_name in audit file: {record.get('model_name')}")

if record.get("audit_required") is not True:
    raise SystemExit("audit_required is not true in audit file")

if record.get("audit_logged") is not True:
    raise SystemExit("audit_logged is not true in audit file")

print("Latest audit file validation passed.")
PY

echo
echo "============================================================"
echo "Phase 2 validation completed successfully."
echo "============================================================"

rm -f /tmp/asr_root_check.json
