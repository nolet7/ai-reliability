# App: asr-ai-quality-service

## Purpose

This folder contains the FastAPI application for the ASR AI Reliability Incident Automation POC.

The app simulates an AI quality prediction service and provides SRE reliability endpoints for:

- Health checks
- Model readiness
- Model visibility
- Prediction audit
- Trace correlation
- Latency simulation
- Error simulation

---

## Main Endpoints

| Endpoint | Purpose |
|---|---|
| `/` | Basic service information |
| `/health/live` | Liveness check for Kubernetes |
| `/health/ready` | Readiness check for Kubernetes |
| `/health/model` | Confirms model artifact is loaded |
| `/version` | Shows service and model metadata |
| `/predict` | Simulates AI prediction |
| `/simulate-latency` | Simulates slow service behavior |
| `/simulate-error` | Simulates application error |

---

## SRE Reliability Fields

The app exposes and returns these fields:

```text
service_name
environment
owner
model_name
model_version
artifact_loaded
request_id
trace_id
audit_required
audit_logged
prediction_status
timestamp_utc
Why This Matters

This service supports the POC reliability layer by giving Dynatrace, OpenTelemetry, ServiceNow, Atlas, Kubernetes, Istio, and CI/CD workflows clear evidence to validate.

Examples:

/health/live supports Kubernetes liveness probes.
/health/ready supports Kubernetes readiness probes.
/health/model supports model readiness validation.
/predict creates request and audit evidence.
/simulate-latency helps trigger latency incidents.
/simulate-error helps trigger error-rate incidents.
