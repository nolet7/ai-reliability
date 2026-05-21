# Rollback Checklist

## Purpose

This checklist defines how to safely roll back AS AI quality service traffic during a failed release or failed canary.

---

## Rollback Scenario

Use rollback when any of these occur:

- Canary version returns elevated errors
- Canary version has high latency
- Model readiness fails
- Prediction audit fails
- Dynatrace detects degraded service health
- Atlas detects schema drift during release
- Kubernetes pods fail readiness
- ServiceNow incident requires immediate mitigation

---

## Rollback Command

Run:

./scripts/apply_ai_rollback.sh

---

## Expected Istio Result

Traffic should be routed as:

- 100% to v1
- 0% to v2

Expected stable model version:

v1.0.3

---

## Rollback Validation Command

Run:

export ISTIO_INGRESS_IP=139.144.255.92
REQUEST_COUNT=30 ./scripts/validate_istio_traffic_split.sh

Expected result:

30 v1.0.3

---

## Kubernetes Validation

Run:

kubectl get pods -n ai-reliability-poc --show-labels

Expected:

- v1 pods are Running
- v1 pods are Ready
- v1 pods show 2/2 because of Istio sidecar
- v2 canary is scaled down or receiving 0% traffic

---

## Application Validation

Run:

curl -s http://139.144.255.192/health/model | python -m json.tool

Expected:

status = model_ready
model_version = v1.0.3
artifact_loaded = true

---

## Prediction Audit Validation

Run:

curl -s -X POST http://139.144.255.192/predict \
  -H "Content-Type: application/json" \
  -H "x-trace-id: rollback-validation-trace-001" \
  -d '{
    "asset_id": "asset-rollback-1001",
    "site_id": "site-as-poc-001",
    "sensor_score": 91,
    "audit_required": true
  }' | python -m json.tool

Expected:

prediction_status = success
audit_logged = true
trace_id = rollback-validation-trace-001

---

## Dynatrace Evidence

Capture:

- Service health
- Failed requests
- Response time
- Endpoint view
- Trace example
- Traffic after rollback

---

## ServiceNow Evidence

Update incident work notes with:

- Rollback command executed
- Time rollback started
- Time rollback completed
- Traffic validation result
- Dynatrace evidence
- Kubernetes pod status
- Final service health

---

## Rollback Completion Criteria

Rollback is complete when:

- Istio traffic returns only v1.0.3
- /health/model returns model_ready
- /predict returns audit_logged=true
- Kubernetes pods are Running and Ready
- Dynatrace no longer shows worsening symptoms
- ServiceNow incident is updated with evidence
