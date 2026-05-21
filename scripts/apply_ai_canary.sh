#!/usr/bin/env bash

# scripts/apply_ai_canary.sh
#
# Purpose:
# Applies ASR AI canary routing through Istio.
#
# This script:
# - Scales v2 canary deployment to 1 replica
# - Applies the 90/10 Istio VirtualService
# - Validates that v1 and v2 pods are present
#
# Traffic result:
# - 90% to v1
# - 10% to v2

set -euo pipefail

NAMESPACE="${NAMESPACE:-ai-reliability-poc}"

echo "============================================================"
echo "ASR AI Reliability POC - Apply Canary Routing"
echo "============================================================"

echo "Step 1: Scaling v2 canary deployment to 1 replica..."
kubectl scale deployment asr-ai-quality-service-v2 -n "${NAMESPACE}" --replicas=1

echo
echo "Step 2: Waiting for v2 rollout..."
kubectl rollout status deployment/asr-ai-quality-service-v2 -n "${NAMESPACE}"

echo
echo "Step 3: Applying 90/10 canary VirtualService..."
kubectl apply -f istio/virtual-service-canary.yaml

echo
echo "Step 4: Current Istio VirtualService..."
kubectl describe virtualservice asr-ai-quality-virtual-service -n "${NAMESPACE}"

echo
echo "Step 5: Current pods..."
kubectl get pods -n "${NAMESPACE}" --show-labels

echo
echo "============================================================"
echo "Canary routing applied successfully."
echo "Expected traffic: 90% v1, 10% v2"
echo "============================================================"
