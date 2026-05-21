# Dynatrace Dashboard Design

## Purpose

This dashboard design supports the ASR AI Reliability Incident Automation POC.

The dashboard should help SREs quickly answer:

- Is the service healthy?
- Is the model loaded?
- Which model version is running?
- Are prediction requests succeeding?
- Are latency or error rates increasing?
- Are audit records being created?
- Are Kubernetes pods healthy?
- Is there enough evidence for ServiceNow incident triage?

---

## Dashboard Name

ASR AI Reliability - Service Health and Incident Evidence

---

## Dashboard Filters

Recommended dashboard filters:

- Environment: poc
- Service Name: asr-ai-quality-service
- Model Name: asr-quality-classifier
- Model Version: v1.0.3
- Kubernetes Namespace: ai-reliability-poc

---

## Panel 1: Service Availability

Purpose:
Show whether the service is reachable and responding successfully.

Signals:

- HTTP 2xx rate
- HTTP 5xx rate
- Service availability percentage

Incident Use:
Use this panel when investigating application availability or error-rate incidents.

---

## Panel 2: API Latency

Purpose:
Track response time for the /predict endpoint.

Signals:

- p50 latency
- p95 latency
- p99 latency

POC Target:
p95 latency should stay below 1.5 seconds.

Incident Use:
Use this panel when /simulate-latency generates slow responses.

---

## Panel 3: Error Rate

Purpose:
Track controlled and unexpected service errors.

Signals:

- HTTP 500 count
- Error percentage
- Failed requests by endpoint

Incident Use:
Use this panel when /simulate-error is used to trigger a reliability incident.

---

## Panel 4: Model Readiness

Purpose:
Show whether the model artifact is loaded.

Signals:

- /health/model response
- artifact_loaded
- model_name
- model_version

Expected Values:

- model_name: asr-quality-classifier
- model_version: v1.0.3
- artifact_loaded: true

Incident Use:
Use this panel when model readiness fails or when a release deploys the wrong model version.

---

## Panel 5: Prediction Audit Evidence

Purpose:
Show whether prediction requests are producing audit evidence.

Signals:

- request_id
- trace_id
- audit_required
- audit_logged
- prediction_status

POC Target:
audit_logged should be true when audit_required is true.

Incident Use:
Use this panel when prediction audit evidence is missing.

---

## Panel 6: Kubernetes Runtime Health

Purpose:
Show pod and deployment health.

Signals:

- Ready pods
- Desired replicas
- Restart count
- Container status
- Readiness probe result
- Liveness probe result

Expected:
2 pods should be running and ready.

Incident Use:
Use this panel when pods restart, fail readiness, or fail liveness checks.

---

## Panel 7: Trace Correlation

Purpose:
Connect user/API requests to distributed traces.

Signals:

- trace_id
- request_id
- service.name
- asr.model_version
- asr.audit_logged
- asr.prediction_status

Incident Use:
Use this panel to connect Dynatrace traces to ServiceNow incident evidence.

---

## Panel 8: Schema Drift Evidence

Purpose:
Show database schema integrity status from Atlas-generated evidence.

Signals:

- schema drift status
- schema-drift-summary.txt
- schema-drift-detected.sql
- ServiceNow drift payload

Expected:
NO_DRIFT

Incident Use:
Use this panel when Atlas detects unauthorized database schema changes.

---

## ServiceNow Incident Evidence Fields

When opening or reviewing an incident, capture:

- service_name
- environment
- model_name
- model_version
- request_id
- trace_id
- audit_logged
- prediction_status
- Dynatrace dashboard URL
- Dynatrace trace URL
- Kubernetes namespace
- Kubernetes pod name
- Atlas drift output, if database drift is involved
- Runbook URL
