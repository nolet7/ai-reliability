# Istio Traffic Safety Evidence

## Purpose

This document captures evidence that the AS AI Reliability POC supports Istio-based traffic safety.

The implemented controls include:

- Istio sidecar injection
- Istio Gateway
- DestinationRule subsets
- Canary routing
- Rollback routing
- Traffic split validation scripts

---

## Namespace

ai-reliability-poc

---

## Stable Version

Deployment:

as-ai-quality-service

Version label:

version=v1

Model version:

v1.0.3

Replicas:

2

Status:

Running with Istio sidecar injection

Expected pod readiness:

2/2

---

## Canary Version

Deployment:

as-ai-quality-service-v2

Version label:

version=v2

Model version:

v1.0.4

Replicas during canary:

1

Replicas after rollback:

0

Status:

Canary was tested and then scaled down after rollback.

---

## Istio Objects

Gateway:

as-ai-quality-gateway

DestinationRule:

as-ai-quality-destination-rule

VirtualService:

as-ai-quality-virtual-service

Istio IngressGateway IP:

139.144.255.92

---

## Canary Route

File:

istio/virtual-service-canary.yaml

Traffic split:

- 90% to v1
- 10% to v2

Validation:

Traffic test showed both model versions were reachable through Istio.

Example evidence:

- v1.0.3 responses observed
- v1.0.4 responses observed

This proves Istio was routing traffic to both stable and canary versions.

---

## Rollback Route

File:

istio/virtual-service-rollback.yaml

Traffic split:

- 100% to v1
- 0% to v2

Validation command:

REQUEST_COUNT=30 ./scripts/validate_istio_traffic_split.sh

Validation result:

30 v1.0.3

This proves rollback successfully routed all traffic back to the stable version.

---

## Reusable Scripts

Canary script:

scripts/apply_ai_canary.sh

Rollback script:

scripts/apply_ai_rollback.sh

Traffic validation script:

scripts/validate_istio_traffic_split.sh

---

## SRE Value

This traffic safety layer proves that the AS AI Reliability POC can support controlled release practices.

The SRE team can:

- Release a new model/application version as a canary
- Send a small percentage of traffic to v2
- Validate latency, errors, model readiness, and audit logging
- Roll traffic back to v1 if the canary fails
- Capture evidence for ServiceNow and RCA

---

## Incident Response Use

If Dynatrace detects increased error rate or latency during canary, the team can run:

scripts/apply_ai_rollback.sh

Then validate:

REQUEST_COUNT=30 ./scripts/validate_istio_traffic_split.sh

Expected rollback evidence:

30 v1.0.3

---

## Status

Istio traffic safety phase completed.
