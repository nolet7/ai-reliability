# Dynatrace DQL Queries

## Purpose

This file documents Dynatrace DQL query ideas for the ASR AI Reliability Incident Automation POC.

These queries support:

- Incident triage
- SLO evidence
- Model version visibility
- Prediction audit validation
- Trace correlation
- ServiceNow incident evidence

---

## Service Name

asr-ai-quality-service

---

## Expected Model Metadata

service.name: asr-ai-quality-service
deployment.environment: poc
model.name: asr-quality-classifier
model.version: v1.0.3
team.owner: sre-platform-team

---

## Query 1: Find ASR Service Logs

DQL:

fetch logs
| filter contains(content, "asr-ai-quality-service")
| sort timestamp desc

Purpose:
Find recent logs for the ASR AI quality service.

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

- asr.service_name
- asr.environment
- asr.model_name
- asr.model_version
- asr.request_id
- asr.trace_id
- asr.asset_id
- asr.site_id
- asr.audit_required
- asr.audit_logged
- asr.prediction_status
- asr.quality_risk
- asr.confidence

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
