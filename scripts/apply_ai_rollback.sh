#!/usr/bin/env bash

# scripts/apply_ai_rollback.sh
#
# Purpose:
# Applies ASR AI rollback routing through Istio.
#
# This script:
# - Applies the rollback VirtualService
# - Routes 100% traffic to v1
# - Optionally scales v2 to 0 replicas
#
# Traffic result:
# - 100% to v1
# - 0% to v2

set -euo pipefail

NAMESPACE="${NAMESPACE:-ai-reliability-poc}"
SCALE_V2_DOWN="${SCALE_V2_DOWN:-true}"

echo "============================================================"
echo "ASR AI Reliability POC - Apply Rollback Routing"
echo "============================================================"

echo "Step 1: Applying rollback VirtualService..."
kubectl apply -f istio/virtual-service-rollback.yaml

echo
echo "Step 2: Current Istio VirtualService..."
kubectl describe virtualservice asr-ai-quality-virtual-service -n "${NAMESPACE}"

if [ "${SCALE_V2_DOWN}" = "true" ]; then
  echo
  echo "Step 3: Scaling v2 canary deployment to 0 replicas..."
  kubectl scale deployment asr-ai-quality-service-v2 -n "${NAMESPACE}" --replicas=0
else
  echo
  echo "Step 3: Leaving v2 deployment running because SCALE_V2_DOWN=false."
fi

echo
echo "Step 4: Current pods..."
kubectl get pods -n "${NAMESPACE}" --show-labels

echo
echo "============================================================"
echo "Rollback routing applied successfully."
echo "Expected traffic: 100% v1, 0% v2"
echo "============================================================"
