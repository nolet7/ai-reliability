# Release Gate Evidence Template

## Purpose

This template captures evidence from the ASR AI Reliability POC release gate validation.

It is used for:

- Release approval
- ServiceNow incident evidence
- RCA documentation
- SRE audit readiness
- Interview/demo storytelling

---

## Release Information

Project:

ASR AI Reliability Incident Automation POC

Service:

asr-ai-quality-service

Environment:

poc

Namespace:

ai-reliability-poc

Model:

asr-quality-classifier

Expected Model Version:

v1.0.3

---

## Validation Command

Command:

./scripts/run_release_gates.sh

---

## Gate Results

### Gate 1: Kubernetes Rollout Status

Status:

PASS / FAIL

Evidence:

kubectl rollout status deployment/asr-ai-quality-service -n ai-reliability-poc

---

### Gate 2: Pod Readiness

Status:

PASS / FAIL

Evidence:

kubectl get pods -n ai-reliability-poc -l app.kubernetes.io/name=asr-ai-quality-service -o wide

Expected:

Pods are Running and Ready.

For Istio-injected pods, expected readiness is:

2/2

---

### Gate 3: Liveness Health

Status:

PASS / FAIL

Endpoint:

/health/live

Expected:

status = live

---

### Gate 4: Readiness Health

Status:

PASS / FAIL

Endpoint:

/health/ready

Expected:

status = ready

---

### Gate 5: Model Readiness

Status:

PASS / FAIL

Endpoint:

/health/model

Expected:

status = model_ready
artifact_loaded = true
model_version = v1.0.3

---

### Gate 6: Prediction Audit

Status:

PASS / FAIL

Endpoint:

/predict

Expected:

prediction_status = success
audit_required = true
audit_logged = true
trace_id present
request_id present

---

### Gate 7: Atlas Schema Drift

Status:

PASS / FAIL

Command:

./scripts/run_atlas_drift_check.sh

Expected:

NO_DRIFT
Schemas are synced, no changes to be made.

Evidence files:

local/generated/atlas/schema-drift-status.txt

---

### Gate 8: Istio Rollback Safety

Status:

PASS / FAIL

Command:

REQUEST_COUNT=30 ./scripts/validate_istio_traffic_split.sh

Expected:

30 v1.0.3

Meaning:

100% traffic is routed to stable v1 during rollback mode.

---

## Failure Handling

If any gate fails:

1. Stop deployment promotion.
2. Capture command output.
3. Run rollback if traffic safety is impacted.
4. Create ServiceNow release gate incident.
5. Attach evidence to RCA.
6. Fix the failed control.
7. Re-run release gates.

---

## ServiceNow Incident Payload

Use:

servicenow/sample-release-gate-incident-payload.json

Or wrapper:

servicenow/create_incident_from_release_gate.sh

---

## Approval Notes

Release approver:

Date:

Decision:

Approved / Rejected

Reason:

