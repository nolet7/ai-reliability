# Dynatrace DQL Queries

## Purpose

This file documents Dynatrace DQL query ideas for the AS AI Reliability Incident Automation POC.

These queries support:

- Incident triage
- SLO evidence
- Model version visibility
- Prediction audit validation
- Trace correlation
- ServiceNow incident evidence

---

## Service Name

as-ai-quality-service

---

## Expected Model Metadata

service.name: as-ai-quality-service
deployment.environment: poc
model.name: as-quality-classifier
model.version: v1.0.3
team.owner: sre-platform-team

---

## Query 1: Find AS Service Logs

DQL:

fetch logs
| filter contains(content, "as-ai-quality-service")
| sort timestamp desc

Purpose:
Find recent logs for the AS AI quality service.

---

## Query 2: Find Prediction Requests

DQL:

fetch logs
| filter contains(content, "/predict")
| sort timestamp desc

Purpose:
Find prediction traffic during incident investigation.

---

## Query 3: Find Simulated Errors

DQL:

fetch logs
| filter contains(content, "simulate-error")
| sort timestamp desc

Purpose:
Find controlled HTTP 500 errors used for incident testing.

---

## Query 4: Find Simulated Latency

DQL:

fetch logs
| filter contains(content, "simulate-latency")
| sort timestamp desc

Purpose:
Find controlled latency traffic used for Dynatrace problem testing.

---

## Query 5: Trace Evidence Fields

Expected trace/span attributes from the application:

- as.service_name
- as.environment
- as.model_name
- as.model_version
- as.request_id
- as.trace_id
- as.asset_id
- as.site_id
- as.audit_required
- as.audit_logged
- as.prediction_status
- as.quality_risk
- as.confidence

---

## Incident Evidence Checklist

When creating or reviewing a ServiceNow incident, capture:

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
- SLO breached
- Runbook URL
