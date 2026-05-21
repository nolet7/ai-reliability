#!/usr/bin/env bash

# scripts/check_dynatrace_otel_export.sh
#
# Purpose:
# Checks recent Kubernetes logs for Dynatrace OTLP export errors.

set -euo pipefail

NAMESPACE="${NAMESPACE:-ai-reliability-poc}"
APP_NAME="${APP_NAME:-asr-ai-quality-service}"
SINCE="${SINCE:-5m}"

echo "Checking Dynatrace OTLP export errors..."
echo "Namespace: ${NAMESPACE}"
echo "App: ${APP_NAME}"
echo "Since: ${SINCE}"
echo

kubectl logs -n "${NAMESPACE}" \
  -l app.kubernetes.io/name="${APP_NAME}" \
  --since="${SINCE}" | grep -i "failed to export\|401\|403\|timeout\|missing authorization\|otlp" || true

echo
echo "If no error lines appeared above, recent OTLP export looks clean."
