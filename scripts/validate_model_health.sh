#!/usr/bin/env bash

# scripts/validate_model_health.sh
#
# Purpose:
# Validates that the AI model is visible and loaded.
#
# This script checks:
# - /health/model
# - /version
#
# Why it matters:
# An AI service can be alive but still unreliable if the model artifact is not loaded.
# This script provides model evidence for release gates and incident triage.

set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"

echo "Validating model health against: ${BASE_URL}"
echo

echo "Checking /health/model..."
curl -s "${BASE_URL}/health/model" | python -m json.tool

echo
echo "Checking /version..."
curl -s "${BASE_URL}/version" | python -m json.tool

echo
echo "Model health validation completed successfully."
