# ServiceNow Incident Field Mapping

## Purpose

This file defines how ASR AI Reliability POC evidence maps into a ServiceNow incident.

The goal is to make incidents actionable, not generic.

---

## Incident Sources

This POC supports incidents from:

- Dynatrace runtime problems
- Atlas schema drift detection
- Kubernetes runtime failures
- CI/CD release gate failures
- Prediction audit failures
- Model readiness failures

---

## Standard ServiceNow Incident Fields

short_description:
Short summary of the issue.

description:
Detailed incident evidence, including service, environment, symptom, and recommended action.

assignment_group:
SRE Platform Operations

cmdb_ci:
ASR AI Quality Service

business_service:
ASR AI Reliability Platform

category:
Application Reliability

subcategory:
AI Inference Service

impact:
2

urgency:
2

severity:
High

state:
New

---

## ASR Reliability Evidence Fields

service_name:
asr-ai-quality-service

environment:
poc

model_name:
asr-quality-classifier

model_version:
v1.0.3

kubernetes_namespace:
ai-reliability-poc

kubernetes_deployment:
asr-ai-quality-service

load_balancer_ip:
139.144.255.192

runbook_url:
runbooks/asr-ai-quality-service.md

---

## Dynatrace Incident Evidence

When the incident source is Dynatrace, include:

dynatrace_service_name:
asr-ai-quality-service

dynatrace_service_url:
Paste Dynatrace service URL here.

dynatrace_trace_url:
Paste Dynatrace trace URL here.

affected_endpoint:
Example: POST /predict

symptom:
Example: High latency, increased error rate, failed requests, or degraded throughput.

observed_metrics:
- Response time
- Failed requests
- Throughput
- Endpoint failure rate

trace_id:
Example: dynatrace-final-trace-1

request_id:
Example: req-xxxxxxxxxxxx

---

## Atlas Schema Drift Evidence

When the incident source is Atlas, include:

source:
Atlas

event_type:
schema_drift

database:
asr_ai_poc

approved_schema:
database/schema-atlas.sql

atlas_diff_file:
local/generated/atlas/schema-drift-detected.sql

atlas_summary_file:
local/generated/atlas/schema-drift-summary.txt

risk:
Live database schema does not match the approved Git schema.

recommended_action:
Review Atlas diff, confirm whether the schema change was approved, and either remove the drift or promote it through the approved migration process.

---

## Kubernetes Runtime Evidence

When the incident source is Kubernetes, include:

namespace:
ai-reliability-poc

deployment:
asr-ai-quality-service

pods:
Use kubectl get pods -n ai-reliability-poc -o wide

logs:
Use kubectl logs -n ai-reliability-poc -l app.kubernetes.io/name=asr-ai-quality-service --tail=100

symptom:
Pod not ready, container restart, failed readiness probe, failed liveness probe, or image pull failure.

---

## Example Dynatrace Incident Short Description

Dynatrace detected high error rate on asr-ai-quality-service in poc

---

## Example Atlas Incident Short Description

Atlas detected PostgreSQL schema drift for asr_ai_poc in poc

---

## Example Incident Description Template

Service:
asr-ai-quality-service

Environment:
poc

Model:
asr-quality-classifier v1.0.3

Symptom:
Describe the observed reliability issue.

Evidence:
- Dynatrace service URL:
- Dynatrace trace URL:
- Kubernetes namespace:
- Kubernetes pod:
- Atlas diff file:
- Request ID:
- Trace ID:

Business / SRE Impact:
The issue may affect prediction reliability, audit evidence, release safety, or database integrity.

Recommended Action:
Follow the runbook, validate recent changes, review Dynatrace evidence, check Kubernetes logs, and confirm whether rollback or schema remediation is required.

Runbook:
runbooks/asr-ai-quality-service.md
