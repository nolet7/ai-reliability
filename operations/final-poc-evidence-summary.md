# AS AI Reliability POC — Final Evidence Summary

## Project Name

AS AI Reliability Incident Automation POC

---

## Current Status

The POC has successfully validated:

- FastAPI AI reliability service
- Docker containerization
- Kubernetes deployment
- LoadBalancer access
- PostgreSQL schema management
- Atlas schema drift detection
- OpenTelemetry instrumentation
- Dynatrace OTLP trace export
- ServiceNow incident automation

---

## Application Evidence

Service:

as-ai-quality-service

Environment:

poc

Model:

as-quality-classifier

Model Version:

v1.0.3

Validated endpoints:

- /health/live
- /health/ready
- /health/model
- /version
- /predict
- /simulate-latency
- /simulate-error

---

## Kubernetes Evidence

Namespace:

ai-reliability-poc

Deployment:

as-ai-quality-service

Service Type:

LoadBalancer

LoadBalancer IP:

139.144.255.192

Runtime controls implemented:

- Dedicated ServiceAccount
- RBAC
- NetworkPolicy
- Liveness probe
- Readiness probe
- Startup probe
- CPU and memory requests
- CPU and memory limits
- Non-root container runtime

---

## PostgreSQL and Atlas Evidence

Database:

as_ai_poc

Approved schema:

database/schema-atlas.sql

Atlas drift script:

scripts/run_atlas_drift_check.sh

Validated behavior:

- Atlas detects unauthorized schema drift
- Atlas generates schema drift evidence
- Atlas generates ServiceNow-ready drift payload
- Drift remediation returns NO_DRIFT

Drift evidence files:

- local/generated/atlas/schema-drift-detected.sql
- local/generated/atlas/schema-drift-summary.txt
- local/generated/atlas/servicenow-schema-drift-payload.json
- local/generated/atlas/schema-drift-status.txt

---

## Dynatrace Evidence

Dynatrace OTLP integration:

Connected

Service visible in Dynatrace:

as-ai-quality-service

Validated telemetry:

- OpenTelemetry enabled in Kubernetes pod
- OTLP endpoint configured
- OTLP headers configured
- OTLP protocol configured as http/protobuf
- Recent export logs showed no 401, 403, timeout, or missing authorization errors after final token correction

Dynatrace evidence value:

- Service-level response time
- Failed request visibility
- Throughput visibility
- Endpoint visibility
- Trace correlation
- Model/version metadata for incident triage

---

## ServiceNow Evidence

ServiceNow instance:

https://dev356687.service-now.com

Incident automation script:

servicenow/create_incident_from_payload.sh

Auth test script:

servicenow/test_servicenow_auth.sh

Validated ServiceNow behavior:

- Authentication test passed
- Incident table access confirmed
- Real test incidents created
- Duplicate protection works using correlation_id
- Atlas drift incident matched existing incident by correlation_id

Known incident examples:

- INC0010001 — AS AI Reliability POC test incident from automation
- INC0010002 — AS AI Reliability POC minimal test incident
- INC0010003 — AS manual test incident
- INC0010006 — Atlas schema drift incident

---

## Incident Types Supported

Dynatrace runtime incident:

- High latency
- Failed requests
- Service degradation
- Endpoint failure

Atlas schema drift incident:

- Unauthorized PostgreSQL schema change
- Live schema differs from approved Git schema

Release gate incident:

- Health check failure
- Model readiness failure
- Audit validation failure
- Kubernetes readiness failure
- Atlas schema drift failure

---

## Key Reliability Controls Implemented

Health checks:

- /health/live
- /health/ready
- /health/model

Model visibility:

- model_name
- model_version
- artifact_loaded

Prediction audit:

- request_id
- trace_id
- audit_required
- audit_logged

Runtime controls:

- Kubernetes probes
- RBAC
- NetworkPolicy
- Resource limits
- Non-root container

Database controls:

- Approved schema in Git
- Atlas drift detection
- Drift evidence generation

Observability controls:

- OpenTelemetry
- Dynatrace OTLP export
- DQL documentation
- Dashboard design documentation
- SLO catalog

Incident controls:

- ServiceNow payload mapping
- Incident creation script
- Duplicate detection
- Dynatrace payload wrapper
- Atlas drift payload wrapper
- Release gate payload wrapper

---

## Interview Story

I built an AS AI Reliability POC that connected application health, Kubernetes runtime controls, OpenTelemetry tracing, Dynatrace observability, Atlas schema drift detection, and ServiceNow incident automation.

The service exposes liveness, readiness, and model-health endpoints, along with model name, model version, artifact-loaded status, request ID, trace ID, and audit evidence. I deployed the service to Kubernetes with probes, resource limits, RBAC, NetworkPolicy, and a LoadBalancer.

I integrated OpenTelemetry with Dynatrace using OTLP and validated that the service appeared in Dynatrace without export errors. I also implemented Atlas schema drift detection against PostgreSQL so unauthorized schema changes generate drift evidence and ServiceNow-ready payloads.

Finally, I automated ServiceNow incident creation using safe environment variables, duplicate protection through correlation IDs, and payloads for Dynatrace runtime issues, Atlas schema drift, and release gate failures.

---

## Next Phase

Phase 8 — Istio Traffic Safety

Planned controls:

- Istio mTLS
- Canary routing
- Rollback routing
- Traffic split validation
- Canary failure simulation
- Rollback evidence capture
