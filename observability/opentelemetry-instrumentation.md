# OpenTelemetry Instrumentation

## Purpose

This document explains how OpenTelemetry is used in the ASR AI Reliability Incident Automation POC.

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
asr-ai-quality-service
Current Phase 6 Scope

At this stage, OpenTelemetry is installed and FastAPI instrumentation is enabled.

The application is now prepared to create request traces internally.

Dynatrace export is not enabled yet.

That will come later when we configure an OTLP endpoint.

OpenTelemetry Resource Attributes

The application defines these OpenTelemetry resource attributes:

Attribute	Example
service.name	asr-ai-quality-service
service.namespace	asr-ai-reliability
deployment.environment	poc
service.version	v1.0.3
model.name	asr-quality-classifier
model.version	v1.0.3
team.owner	sre-platform-team
Prediction Span Attributes

The /predict endpoint adds custom span attributes:

Attribute	Purpose
asr.service_name	Service identity
asr.environment	Runtime environment
asr.model_name	Model identity
asr.model_version	Model version
asr.artifact_loaded	Whether the model artifact is loaded
asr.request_id	Prediction request ID
asr.trace_id	Caller-provided or locally generated trace ID
asr.asset_id	Asset being scored
asr.site_id	Site or facility ID
asr.sensor_score	Input score used by the POC prediction
asr.audit_required_input	Whether the caller requested audit
asr.audit_required	Final audit requirement
asr.audit_logged	Whether audit evidence was written
asr.prediction_status	Prediction result status
asr.quality_risk	Low, medium, or high
asr.confidence	Prediction confidence
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
