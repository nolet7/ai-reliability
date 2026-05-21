# OpenTelemetry Instrumentation

## Purpose

This document explains how OpenTelemetry is used in the AS AI Reliability Incident Automation POC.

OpenTelemetry prepares the service for trace correlation across:

- FastAPI HTTP requests
- Prediction audit events
- Model metadata
- Service version
- Runtime environment
- Dynatrace problem investigation
- ServiceNow incident evidence

---

## Instrumented Service

```text
as-ai-quality-service
Current Phase 6 Scope

At this stage, OpenTelemetry is installed and FastAPI instrumentation is enabled.

The application is now prepared to create request traces internally.

Dynatrace export is not enabled yet.

That will come later when we configure an OTLP endpoint.

OpenTelemetry Resource Attributes

The application defines these OpenTelemetry resource attributes:

Attribute	Example
service.name	as-ai-quality-service
service.namespace	as-ai-reliability
deployment.environment	poc
service.version	v1.0.3
model.name	as-quality-classifier
model.version	v1.0.3
team.owner	sre-platform-team
Prediction Span Attributes

The /predict endpoint adds custom span attributes:

Attribute	Purpose
as.service_name	Service identity
as.environment	Runtime environment
as.model_name	Model identity
as.model_version	Model version
as.artifact_loaded	Whether the model artifact is loaded
as.request_id	Prediction request ID
as.trace_id	Caller-provided or locally generated trace ID
as.asset_id	Asset being scored
as.site_id	Site or facility ID
as.sensor_score	Input score used by the POC prediction
as.audit_required_input	Whether the caller requested audit
as.audit_required	Final audit requirement
as.audit_logged	Whether audit evidence was written
as.prediction_status	Prediction result status
as.quality_risk	Low, medium, or high
as.confidence	Prediction confidence
Local POC Mode

By default:

OTEL_ENABLED=true

The service is instrumented, but no external telemetry backend is configured yet.

Future Dynatrace Mode

Later we will configure:

OTEL_EXPORTER_OTLP_ENDPOINT=<dynatrace-or-otel-collector-endpoint>

That will allow traces to be exported to Dynatrace or to an OpenTelemetry Collector.

Why This Matters

When an incident happens, SREs need to correlate:

request_id
trace_id
service_name
model_name
model_version
audit_logged
prediction_status
latency
error rate

This gives Dynatrace and ServiceNow stronger evidence for triage, RCA, and incident closure.
