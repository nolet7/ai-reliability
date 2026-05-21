#!/usr/bin/env bash

# scripts/validate_istio_traffic_split.sh
#
# Purpose:
# Validates Istio traffic routing by calling /version repeatedly
# and counting returned model versions.
#
# Usage:
# ISTIO_INGRESS_IP=139.144.255.92 REQUEST_COUNT=100 ./scripts/validate_istio_traffic_split.sh

set -euo pipefail

ISTIO_INGRESS_IP="${ISTIO_INGRESS_IP:-}"
REQUEST_COUNT="${REQUEST_COUNT:-50}"

if [ -z "${ISTIO_INGRESS_IP}" ]; then
  echo "ISTIO_INGRESS_IP is required."
  echo "Example:"
  echo "export ISTIO_INGRESS_IP=139.144.255.92"
  exit 1
fi

echo "============================================================"
echo "AS AI Reliability POC - Istio Traffic Split Validation"
echo "============================================================"
echo "Istio Ingress IP: ${ISTIO_INGRESS_IP}"
echo "Request count: ${REQUEST_COUNT}"
echo

for i in $(seq 1 "${REQUEST_COUNT}"); do
  curl -s "http://${ISTIO_INGRESS_IP}/version" \
    | python -c "import sys,json; print(json.load(sys.stdin)['model_version'])"
done | sort | uniq -c

echo
echo "============================================================"
echo "Traffic split validation completed."
echo "============================================================"
