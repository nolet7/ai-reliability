# Dynatrace Evidence Checklist

## Purpose

This file captures the evidence needed to prove that the ASR AI Reliability POC is visible in Dynatrace.

This evidence will later be used in ServiceNow incidents, RCA notes, and interview/demo documentation.

---

## Dynatrace Service Evidence

Service detected in Dynatrace:

asr-ai-quality-service

Expected Dynatrace areas:

- Services
- Distributed traces
- Endpoints
- Response time
- Failed requests
- Throughput
- Related logs

---

## Endpoint Evidence

Observed endpoints:

- GET /health/model
- POST /predict
- GET /health/ready
- GET /health/live
- GET /simulate-latency
- GET /simulate-error

---

## Required Screenshot Evidence

Capture screenshots for:

- Dynatrace service overview page
- Service response time chart
- Failed requests chart
- Throughput chart
- Endpoint list showing /predict
- Endpoint list showing /health/model
- Trace or request detail page
- Related logs section if available

---

## OpenTelemetry Export Evidence

Kubernetes log check command:

kubectl logs -n ai-reliability-poc \
  -l app.kubernetes.io/name=asr-ai-quality-service \
  --since=2m | grep -i "failed to export\|401\|403\|timeout\|missing authorization\|otlp" || true

Expected result:

No output

Meaning:

- No failed export batch
- No 401
- No 403
- No timeout
- No missing authorization

---

## Kubernetes Runtime Evidence

Namespace:

ai-reliability-poc

Deployment:

asr-ai-quality-service

LoadBalancer IP:

139.144.255.192

Validation command:

kubectl get pods -n ai-reliability-poc -o wide

Expected:

Pods are Running and Ready.

---

## Incident Evidence Fields for ServiceNow

When creating a ServiceNow incident later, include:

- service_name: asr-ai-quality-service
- environment: poc
- model_name: asr-quality-classifier
- model_version: v1.0.3
- affected_endpoint
- trace_id
- request_id
- Dynatrace service URL
- Dynatrace trace URL
- error type
- latency symptom
- Kubernetes namespace
- Kubernetes pod name
- runbook URL

---

## Status

Dynatrace connection: confirmed

Service visible: confirmed

OTLP export errors: none after final token correction

Ready for ServiceNow incident automation: yes
