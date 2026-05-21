# Dynatrace Connection Evidence

## Purpose

This document captures proof that the AS AI Reliability POC is connected to Dynatrace through OpenTelemetry OTLP.

---

## Status

Connected

---

## Service Detected in Dynatrace

Service name:

as-ai-quality-service

Dynatrace displayed the service under classic service monitoring with endpoint-level visibility.

---

## Kubernetes Source

Namespace:

ai-reliability-poc

Deployment:

as-ai-quality-service

LoadBalancer IP:

139.144.255.192

---

## OpenTelemetry Configuration

The Kubernetes pod was validated with:

OTEL_ENABLED=true

OTEL_EXPORTER_OTLP_ENDPOINT=https://cye36840.live.dynatrace.com/api/v2/otlp

OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://cye36840.live.dynatrace.com/api/v2/otlp/v1/traces

OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf

OTEL_EXPORTER_OTLP_TRACES_PROTOCOL=http/protobuf

The authorization header was confirmed to be set without printing the token.

---

## Dynatrace Token Scope

Required scope:

openTelemetryTrace.ingest

This scope allows the application to ingest OpenTelemetry traces into Dynatrace.

---

## Traffic Generated

The following traffic was generated through the Kubernetes LoadBalancer:

- /predict
- /health/live
- /health/ready
- /health/model
- /simulate-latency
- /simulate-error

---

## Dynatrace Service Evidence

Observed endpoints:

- GET /health/model
- POST /predict
- GET /health/ready
- GET /health/live

Observed service metrics:

- Response time
- Failed requests
- Throughput
- Endpoint-level traffic

---

## Export Validation

Recent Kubernetes logs were checked for:

- failed to export
- 401
- 403
- timeout
- missing authorization
- otlp

Result:

No recent OTLP export errors were found after the token and endpoint were corrected.

---

## Incident Evidence Value

This proves Dynatrace can now provide runtime evidence for ServiceNow incidents, including:

- affected service
- affected endpoint
- response time
- failure rate
- throughput
- trace context
- model metadata
- environment
- Kubernetes workload

---

## Next Step

Use this Dynatrace service evidence when creating ServiceNow incident payloads in Phase 7.
