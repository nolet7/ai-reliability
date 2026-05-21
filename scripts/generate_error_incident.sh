#!/usr/bin/env bash

# scripts/generate_error_incident.sh
#
# Purpose:
# Generates controlled HTTP 500 errors against the ASR AI quality service.
#
# Why it matters:
# This script will later be used to generate error traffic for Dynatrace problem
# detection and ServiceNow incident routing.

set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"
REQUEST_COUNT="${REQUEST_COUNT:-5}"

echo "Generating error traffic..."
echo "Base URL: ${BASE_URL}"
echo "Request count: ${REQUEST_COUNT}"
echo

for i in $(seq 1 "${REQUEST_COUNT}"); do
  echo "Error request ${i}/${REQUEST_COUNT}"

  HTTP_STATUS="$(curl -s -o /tmp/asr_error_response.json -w "%{http_code}" "${BASE_URL}/simulate-error")"

  echo "HTTP status: ${HTTP_STATUS}"
  cat /tmp/asr_error_response.json | python -m json.tool || cat /tmp/asr_error_response.json
  echo

  if [ "${HTTP_STATUS}" != "500" ]; then
    echo "Expected HTTP 500 but got ${HTTP_STATUS}"
    exit 1
  fi
done

rm -f /tmp/asr_error_response.json

echo "Error simulation completed successfully."
