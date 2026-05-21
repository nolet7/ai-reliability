#!/usr/bin/env bash

# scripts/run_atlas_drift_check.sh
#
# Purpose:
# Detects PostgreSQL schema drift using Atlas.
#
# This script compares:
# - Approved Git schema: database/schema-atlas.sql
# - Live PostgreSQL database: asr_ai_poc
#
# If drift exists, the script:
# - Saves Atlas diff output
# - Creates a drift summary
# - Creates a ServiceNow-ready JSON payload
# - Exits with code 1
#
# If no drift exists, the script:
# - Saves a clean status file
# - Exits with code 0
#
# Why it matters:
# This script becomes a release gate and operational evidence source.
# Later, ServiceNow automation will use the generated payload to create an incident.

set -euo pipefail

APPROVED_SCHEMA="${APPROVED_SCHEMA:-database/schema-atlas.sql}"
LIVE_DB_URL="${LIVE_DB_URL:-postgres://asr_user:asr_password@asr-ai-postgres-poc:5432/asr_ai_poc?sslmode=disable}"
DEV_DB_URL="${DEV_DB_URL:-postgres://asr_user:asr_password@asr-ai-atlas-dev-postgres:5432/dev?sslmode=disable}"

OUTPUT_DIR="${OUTPUT_DIR:-local/generated/atlas}"
DIFF_FILE="${OUTPUT_DIR}/schema-drift-detected.sql"
SUMMARY_FILE="${OUTPUT_DIR}/schema-drift-summary.txt"
STATUS_FILE="${OUTPUT_DIR}/schema-drift-status.txt"
PAYLOAD_FILE="${OUTPUT_DIR}/servicenow-schema-drift-payload.json"

DATABASE_NAME="${DATABASE_NAME:-asr_ai_poc}"
ENVIRONMENT="${ENVIRONMENT:-poc}"
SERVICE_NAME="${SERVICE_NAME:-asr-ai-quality-service}"
CI_NAME="${CI_NAME:-ASR AI PostgreSQL Database}"
ASSIGNMENT_GROUP="${ASSIGNMENT_GROUP:-SRE Platform Operations}"
RUNBOOK_URL="${RUNBOOK_URL:-runbooks/database-schema-drift.md}"

mkdir -p "${OUTPUT_DIR}"

echo "============================================================"
echo "ASR AI Reliability POC - Atlas Schema Drift Check"
echo "============================================================"
echo "Approved schema: ${APPROVED_SCHEMA}"
echo "Live database:   ${DATABASE_NAME}"
echo "Environment:     ${ENVIRONMENT}"
echo

if [ ! -f "${APPROVED_SCHEMA}" ]; then
  echo "Approved schema file not found: ${APPROVED_SCHEMA}"
  exit 1
fi

echo "Running Atlas schema diff..."

set +e
./scripts/atlas.sh schema diff \
  --from "file://${APPROVED_SCHEMA}" \
  --to "${LIVE_DB_URL}" \
  --dev-url "${DEV_DB_URL}" \
  > "${DIFF_FILE}" 2>&1
ATLAS_EXIT_CODE=$?
set -e

if [ "${ATLAS_EXIT_CODE}" -ne 0 ]; then
  echo "Atlas command failed. See ${DIFF_FILE}"
  cat "${DIFF_FILE}"
  exit "${ATLAS_EXIT_CODE}"
fi

echo
echo "Atlas diff output:"
cat "${DIFF_FILE}"
echo

# Atlas commonly prints this when schemas match:
# Schemas are synced, no changes to be made.
#
# We also treat an empty file as no drift.
if [ ! -s "${DIFF_FILE}" ] || grep -q "Schemas are synced, no changes to be made" "${DIFF_FILE}"; then
  cat > "${STATUS_FILE}" <<STATUS_EOF
ASR AI Reliability POC - Schema Drift Status

Status:
NO_DRIFT

Database:
${DATABASE_NAME}

Environment:
${ENVIRONMENT}

Approved Schema:
${APPROVED_SCHEMA}

Result:
Live PostgreSQL schema matches the approved Git schema.

Detection Tool:
Atlas
STATUS_EOF

  echo "No schema drift detected."
  echo "Status file written to: ${STATUS_FILE}"
  echo
  echo "============================================================"
  echo "Atlas drift check passed."
  echo "============================================================"
  exit 0
fi

# If we get here, Atlas found differences.
cat > "${SUMMARY_FILE}" <<SUMMARY_EOF
ASR AI Reliability POC - Schema Drift Evidence

Status:
DRIFT_DETECTED

Drift Type:
Unauthorized live database schema change

Database:
${DATABASE_NAME}

Environment:
${ENVIRONMENT}

Configuration Item:
${CI_NAME}

Affected Service:
${SERVICE_NAME}

Approved Schema:
${APPROVED_SCHEMA}

Detection Tool:
Atlas

Atlas Diff Evidence File:
${DIFF_FILE}

Operational Risk:
The live PostgreSQL schema no longer matches the approved Git schema. This indicates that a database change may have been made outside the approved pull request, release gate, schema review, or ServiceNow change process.

SRE Impact:
Schema drift can cause application mismatch, failed deployments, broken audit assumptions, failed migrations, and incident response confusion.

Recommended Action:
Open a ServiceNow incident or change task, capture Atlas diff evidence, identify the source of the change, decide whether the schema change is valid, and either remove the drift or approve it through the normal schema migration process.
SUMMARY_EOF

python - <<PY
import json
from pathlib import Path
from datetime import datetime, timezone

diff_file = Path("${DIFF_FILE}")
summary_file = Path("${SUMMARY_FILE}")
payload_file = Path("${PAYLOAD_FILE}")

payload = {
    "source": "Atlas",
    "event_type": "schema_drift",
    "short_description": "Atlas detected PostgreSQL schema drift in ${DATABASE_NAME}",
    "description": summary_file.read_text(encoding="utf-8"),
    "configuration_item": "${CI_NAME}",
    "service_name": "${SERVICE_NAME}",
    "environment": "${ENVIRONMENT}",
    "database": "${DATABASE_NAME}",
    "severity": "High",
    "assignment_group": "${ASSIGNMENT_GROUP}",
    "runbook_url": "${RUNBOOK_URL}",
    "approved_schema": "${APPROVED_SCHEMA}",
    "atlas_diff_file": "${DIFF_FILE}",
    "atlas_diff_output": diff_file.read_text(encoding="utf-8"),
    "detected_at_utc": datetime.now(timezone.utc).isoformat(),
    "recommended_action": (
        "Review Atlas diff, validate whether the change was approved, "
        "remove unauthorized drift or promote the change through an approved migration."
    ),
}

payload_file.write_text(json.dumps(payload, indent=2), encoding="utf-8")
print(f"ServiceNow-ready payload written to: {payload_file}")
PY

echo "Schema drift detected."
echo "Diff file: ${DIFF_FILE}"
echo "Summary file: ${SUMMARY_FILE}"
echo "Payload file: ${PAYLOAD_FILE}"
echo
echo "============================================================"
echo "Atlas drift check failed because drift exists."
echo "============================================================"

# Exit 1 intentionally so CI/CD can fail when drift exists.
exit 1
