# Dynatrace Tagging Strategy

## Purpose

This file defines the tagging strategy for the ASR AI Reliability Incident Automation POC.

Tags help Dynatrace, ServiceNow, dashboards, SLOs, and incident routing understand:

- Which service is affected
- Which environment is affected
- Which model version is running
- Which team owns the service
- Which Kubernetes namespace and workload are involved

---

## Required Tags

service_name: asr-ai-quality-service
environment: poc
owner: sre-platform-team
model_name: asr-quality-classifier
model_version: v1.0.3
kubernetes_namespace: ai-reliability-poc
component: inference-api
application: asr-ai-reliability
ci_name: ASR AI Quality Service

---

## Kubernetes Labels Used for Tagging

app.kubernetes.io/name: asr-ai-quality-service
app.kubernetes.io/part-of: asr-ai-reliability
app.kubernetes.io/component: inference-api
app.kubernetes.io/version: v1.0.3
environment: poc
owner: sre-platform-team
model_name: asr-quality-classifier
model_version: v1.0.3

---

## Dynatrace Service Mapping

Dynatrace should map the service as:

service.name: asr-ai-quality-service
service.namespace: asr-ai-reliability
deployment.environment: poc
service.version: v1.0.3
team.owner: sre-platform-team
model.name: asr-quality-classifier
model.version: v1.0.3

---

## ServiceNow Incident Routing Fields

When Dynatrace creates a ServiceNow incident, include:

service_name: asr-ai-quality-service
environment: poc
assignment_group: SRE Platform Operations
configuration_item: ASR AI Quality Service
model_name: asr-quality-classifier
model_version: v1.0.3
runbook_url: runbooks/asr-ai-quality-service.md

---

## Why This Matters

Without consistent tags, incidents become generic and hard to route.

With consistent tags, SRE teams can quickly answer:

- What service is affected?
- What model version is running?
- What environment is impacted?
- Which team owns the service?
- Which runbook should be used?
- Which CI should be attached in ServiceNow?
