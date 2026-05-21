# AS AI Reliability Incident Automation POC

## 1. Project Overview

This project is a proof-of-concept SRE reliability platform for an AI inference service.

The goal is to demonstrate how an enterprise SRE team can monitor, validate, protect, and operate an AI-powered service using:

- Dynatrace for observability and problem detection
- OpenTelemetry for traces, metrics, logs, and trace correlation
- ServiceNow for incident management and operational accountability
- Atlas for PostgreSQL schema drift detection
- Kubernetes for runtime orchestration
- Istio for mTLS, canary routing, and rollback routing
- CI/CD release gates for safe deployments
- Runbooks, escalation matrix, and evidence capture for incident response

The POC focuses on an example AI service called:

```text
as-ai-quality-service
```

This service represents an AI quality prediction API used in a reliability-sensitive enterprise environment.

---

## 2. Main POC Objective

The main objective is to build a reliability layer that can answer these operational questions:

| Question | Evidence Source |
|---|---|
| Is the service alive? | `/health/live` |
| Is the service ready for traffic? | `/health/ready` |
| Is the AI model loaded? | `/health/model` |
| Which model version is running? | `model_name`, `model_version`, `artifact_loaded` |
| Was the prediction audited? | `request_id`, `audit_required`, `audit_logged`, `trace_id` |
| Can we trace a request end-to-end? | OpenTelemetry and Dynatrace |
| Can we detect application latency and errors? | Dynatrace |
| Can we detect Kubernetes runtime issues? | Dynatrace and Kubernetes events |
| Can we detect database schema drift? | Atlas |
| Can we route incidents with evidence? | ServiceNow |
| Can we safely release and rollback? | CI/CD gates and Istio routing |

---

## 3. Target Architecture

```text
AS AI Reliability Incident Automation POC
│
├── Application Layer
│   ├── as-ai-quality-service
│   ├── /predict
│   ├── /simulate-latency
│   ├── /simulate-error
│   └── PostgreSQL dependency
│
├── SRE Reliability Layer
│   ├── Health checks: /health/live, /health/ready, /health/model
│   ├── Model visibility: model_name, model_version, artifact_loaded
│   ├── Prediction audit: request_id, audit_required, audit_logged, trace_id
│   ├── Observability: Dynatrace, OpenTelemetry, DQL, SLO catalog
│   ├── Runtime controls: Kubernetes probes, resource limits, RBAC, NetworkPolicy
│   ├── Traffic safety: Istio mTLS, canary routing, rollback routing
│   ├── Release safety: CI/CD release gates, evidence templates, rollback script
│   └── Operations: runbooks, escalation matrix, evidence capture
│
├── Database Reliability Layer
│   ├── Approved schema in Git
│   ├── Atlas schema drift detection
│   ├── Drift simulation
│   └── Drift incident creation
│
├── Observability and Incident Layer
│   ├── Dynatrace service monitoring
│   ├── OpenTelemetry traces, metrics, and logs
│   ├── Dynatrace DQL queries
│   ├── Dynatrace SLO catalog
│   └── ServiceNow incident creation
│
└── Operations Layer
    ├── Runbooks
    ├── RCA evidence
    ├── Escalation matrix
    ├── Rollback evidence
    └── ServiceNow closure notes
```

---

## 4. Tools Used

| Tool | Purpose |
|---|---|
| Kubernetes | Runs the AI service and supporting workloads |
| Docker | Builds the application container image |
| FastAPI | Provides the AI reliability API |
| PostgreSQL | Stores prediction requests, results, model versions, and audit records |
| Atlas | Detects database schema drift |
| Dynatrace | Observability, dashboards, DQL, problem detection, and SLOs |
| OpenTelemetry | Trace, metric, and log instrumentation |
| ServiceNow | Incident creation, assignment, triage, and closure |
| Istio | mTLS, canary routing, and rollback routing |
| GitHub Actions | CI/CD workflow and release gates |
| Bash scripts | Validation, simulation, rollback, and evidence capture |

---

## 5. SRE Reliability Layer

The SRE Reliability Layer includes:

```text
Health checks
Model visibility
Prediction audit
Observability
Runtime controls
Traffic safety
Release safety
Operations evidence
```

### Health Checks

The service will expose:

| Endpoint | Purpose |
|---|---|
| `/health/live` | Confirms the service process is alive |
| `/health/ready` | Confirms the service is ready for traffic |
| `/health/model` | Confirms the AI model artifact is loaded |

### Model Visibility

The service will expose:

```json
{
  "service_name": "as-ai-quality-service",
  "model_name": "as-quality-classifier",
  "model_version": "v1.0.3",
  "artifact_loaded": true,
  "environment": "poc"
}
```

### Prediction Audit

Each prediction should produce audit evidence:

```json
{
  "request_id": "req-20260520-0001",
  "audit_required": true,
  "audit_logged": true,
  "trace_id": "example-trace-id",
  "model_name": "as-quality-classifier",
  "model_version": "v1.0.3",
  "prediction_status": "success"
}
```

---

## 6. Incident Types Covered

This POC will cover multiple operational incident types.

| Incident Type | Detection Source | Incident Destination |
|---|---|---|
| High API latency | Dynatrace | ServiceNow |
| High API error rate | Dynatrace | ServiceNow |
| Kubernetes pod readiness failure | Dynatrace / Kubernetes | ServiceNow |
| Model artifact not loaded | Health gate / Dynatrace event | ServiceNow |
| Prediction audit missing | App validation / DQL | ServiceNow |
| PostgreSQL schema drift | Atlas | ServiceNow |
| Canary release failure | Dynatrace / CI/CD gate | ServiceNow |
| Istio routing or mTLS issue | Istio / Kubernetes | ServiceNow |

---

## 7. SLO Catalog

Initial POC-level SLOs:

| SLO Name | SLI | POC Target |
|---|---|---|
| API Availability SLO | Successful `/predict` requests / total `/predict` requests | 99% |
| API Latency SLO | p95 latency for `/predict` | less than 1.5s |
| Model Readiness SLO | `/health/model` returns `artifact_loaded=true` | 100% |
| Audit Logging SLO | `audit_logged=true` when `audit_required=true` | 100% |
| Schema Integrity SLO | Approved Git schema matches live DB | 100% |
| Kubernetes Readiness SLO | Ready pods / desired pods | 99% |
| Canary Safety SLO | Canary success rate within threshold | 99% |
| Trace Coverage SLO | Requests with valid `trace_id` | 95% |

---

## 8. Repository Structure

```text
as-ai-incident-poc/
├── app/
├── k8s/
├── istio/
├── database/
├── observability/
├── release-safety/
├── servicenow/
├── runbooks/
├── operations/
├── scripts/
├── .github/workflows/
└── README.md
```

### Folder Purpose

| Folder | Purpose |
|---|---|
| `app/` | FastAPI AI reliability service |
| `k8s/` | Kubernetes manifests |
| `istio/` | Istio mTLS, canary, and rollback routing |
| `database/` | PostgreSQL schema, Atlas config, seed data, drift simulation |
| `observability/` | Dynatrace, OpenTelemetry, DQL, dashboards, and SLO catalog |
| `release-safety/` | Release gate config, rollback checklist, evidence templates |
| `servicenow/` | Incident mapping, payloads, and incident creation scripts |
| `runbooks/` | Operational runbooks |
| `operations/` | Escalation matrix, RCA template, evidence capture |
| `scripts/` | Validation and simulation scripts |
| `.github/workflows/` | CI/CD and release gate workflows |

---

## 9. Build Phases

| Phase | Description |
|---|---|
| Phase 1 | Project foundation |
| Phase 2 | Build the AI reliability service |
| Phase 3 | Containerize and run locally |
| Phase 4 | Add PostgreSQL and Atlas schema drift detection |
| Phase 5 | Deploy to Kubernetes |
| Phase 6 | Add OpenTelemetry and Dynatrace observability |
| Phase 7 | Add ServiceNow incident automation |
| Phase 8 | Add Istio traffic safety |
| Phase 9 | Add CI/CD release gates |
| Phase 10 | Final demo, evidence capture, and interview story |

---

## 10. Success Criteria

The POC is successful when the following are proven:

- The application exposes `/health/live`, `/health/ready`, and `/health/model`
- The application exposes model name, model version, and artifact status
- Prediction requests generate request ID, trace ID, and audit evidence
- Dynatrace detects latency, error, and Kubernetes runtime problems
- OpenTelemetry provides trace correlation
- DQL can query operational evidence
- Atlas detects unauthorized PostgreSQL schema drift
- ServiceNow receives incidents with CI, service, environment, severity, owner, runbook, and evidence
- Kubernetes probes, resource limits, RBAC, and NetworkPolicy are present
- Istio canary and rollback routes are defined
- CI/CD release gates validate health, model, audit, schema, and rollback readiness
- Runbooks, escalation matrix, RCA template, and closure checklist exist

---

## 11. Example Interview Summary

I designed an SRE reliability layer for an AI inference service that went beyond basic monitoring. The service exposed liveness, readiness, and model-health endpoints, including model name, model version, and artifact-loaded status. Each prediction generated audit evidence with request ID, trace ID, audit-required, and audit-logged fields.

Dynatrace and OpenTelemetry provided observability across traces, metrics, logs, Kubernetes runtime, and service health, while DQL queries and an SLO catalog supported evidence-based incident triage. I also added Kubernetes runtime controls such as probes, resource limits, RBAC, and NetworkPolicy, plus Istio mTLS, canary routing, and rollback routing for traffic safety.

For release safety, the CI/CD pipeline included gates for health checks, model readiness, prediction audit logging, Atlas schema drift detection, and rollback readiness. When Dynatrace detected runtime problems or Atlas detected schema drift, ServiceNow incidents were created with the affected CI, service name, environment, severity, model version, dashboard link, trace evidence, Atlas diff output, and runbook.
