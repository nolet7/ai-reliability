#!/usr/bin/env bash

# scripts/generate_latency_incident.sh
#
# Purpose:
# Generates controlled latency against the ASR AI quality service.
#
# Why it matters:
# This script will later be used to create enough slow traffic for Dynatrace
# to detect latency degradation and create a ServiceNow incident.

set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"
SECONDS_DELAY="${SECONDS_DELAY:-2}"
REQUEST_COUNT="${REQUEST_COUNT:-5}"

echo "Generating latency traffic..."
echo "Base URL: ${BASE_URL}"
echo "Delay per request: ${SECONDS_DELAY} seconds"
echo "Request count: ${REQUEST_COUNT}"
echo

for i in $(seq 1 "${REQUEST_COUNT}"); do
  echo "Latency request ${i}/${REQUEST_COUNT}"
  time curl -s "${BASE_URL}/simulate-latency?seconds=${SECONDS_DELAY}" | python -m json.tool
  echo
done

echo "Latency simulation completed."
