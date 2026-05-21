#!/usr/bin/env bash

# scripts/validate_health_endpoints.sh
#
# Purpose:
# Validates the core SRE health endpoints for the AS AI Reliability POC.
#
# This script checks:
# - /health/live
# - /health/ready
#
# Why it matters:
# These endpoints will later be used by Kubernetes probes, CI/CD release gates,
# Dynatrace validation, and incident evidence capture.

set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"

echo "Validating health endpoints against: ${BASE_URL}"
echo

echo "Checking /health/live..."
curl -s "${BASE_URL}/health/live" | python -m json.tool

echo
echo "Checking /health/ready..."
curl -s "${BASE_URL}/health/ready" | python -m json.tool

echo
echo "Health endpoint validation completed successfully."
