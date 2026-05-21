# Observability Validation Checklist

## Purpose

This checklist validates that the AS AI Reliability POC has the required observability evidence before moving to ServiceNow incident automation.

---

## Application Evidence

- [ ] `/health/live` returns live
- [ ] `/health/ready` returns ready
- [ ] `/health/model` returns model_ready
- [ ] `/version` returns service and model metadata
- [ ] `/predict` returns audit_logged=true
- [ ] `/simulate-latency` creates controlled latency
- [ ] `/simulate-error` returns controlled HTTP 500

---

## Kubernetes Evidence

- [ ] Namespace exists: ai-reliability-poc
- [ ] Deployment exists: as-ai-quality-service
- [ ] Service exists: as-ai-quality-service
- [ ] Pods are Running
- [ ] Pods are Ready
- [ ] LoadBalancer IP is available
- [ ] Kubernetes logs show request traffic

---

## OpenTelemetry Evidence

- [ ] OTEL_ENABLED is true inside the pod
- [ ] Service name is as-ai-quality-service
- [ ] Model name is as-quality-classifier
- [ ] Prediction requests include trace_id
- [ ] Prediction requests include request_id
- [ ] Prediction requests include model_version
- [ ] Prediction requests include audit_logged

---

## Dynatrace-Ready Evidence

- [ ] Dynatrace tagging strategy exists
- [ ] DQL query notes exist
- [ ] Dashboard design notes exist
- [ ] SLO catalog exists
- [ ] Model metadata fields are documented
- [ ] Incident evidence fields are documented

---

## Atlas Evidence

- [ ] PostgreSQL database is running
- [ ] Approved schema exists
- [ ] Atlas drift script exists
- [ ] Drift detection works
- [ ] Drift remediation returns NO_DRIFT
- [ ] ServiceNow-ready drift payload can be generated

---

## Ready for Next Phase

Move to ServiceNow automation only when:

- [ ] Kubernetes runtime validation passes
- [ ] OpenTelemetry-enabled deployment is running
- [ ] SLO catalog is documented
- [ ] Dynatrace DQL notes are documented
- [ ] Dashboard design is documented
- [ ] Tagging strategy is documented
- [ ] Atlas drift detection is proven
