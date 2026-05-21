# GitHub Actions Environment Setup

## Purpose

This file documents the GitHub Actions environment setup required for the AS AI Reliability POC automation.

The goal is to safely support:

- Docker image build and push
- Kubernetes deployment
- Dynatrace OTLP configuration
- ServiceNow incident creation
- Atlas schema drift validation
- Istio canary and rollback validation
- Release gate automation

---

## GitHub Environments

Create these environments:

- poc
- production

The first automation target is:

poc

---

## Repository Variables

Create these under:

Settings > Secrets and variables > Actions > Variables

APP_NAME=as-ai-quality-service

NAMESPACE=ai-reliability-poc

DOCKER_IMAGE=noletengine/as-ai-quality-service

IMAGE_TAG=poc

K8S_CONTEXT_NAME=lke605802-ctx

AS_LB_IP=139.144.255.192

ISTIO_INGRESS_IP=139.144.255.92

EXPECTED_MODEL_VERSION=v1.0.3

---

## Repository Secrets

Create these under:

Settings > Secrets and variables > Actions > Secrets

### Docker Hub

DOCKERHUB_USERNAME

DOCKERHUB_TOKEN

---

### Kubernetes

KUBECONFIG_B64

Generate with:

cat ~/.kube/config | base64 | tr -d '\n'

---

### Dynatrace

DT_OTLP_ENDPOINT

DT_OTLP_TRACES_ENDPOINT

DT_OTLP_HEADERS

DT_OTLP_PROTOCOL

Expected values:

DT_OTLP_ENDPOINT=https://cye36840.live.dynatrace.com/api/v2/otlp

DT_OTLP_TRACES_ENDPOINT=https://cye36840.live.dynatrace.com/api/v2/otlp/v1/traces

DT_OTLP_HEADERS=Authorization=Api-Token YOUR_NEW_DYNATRACE_TOKEN

DT_OTLP_PROTOCOL=http/protobuf

The Dynatrace token must include:

openTelemetryTrace.ingest

---

### ServiceNow

SERVICENOW_INSTANCE_URL

SERVICENOW_USERNAME

SERVICENOW_PASSWORD

Example:

SERVICENOW_INSTANCE_URL=https://dev356687.service-now.com

SERVICENOW_USERNAME=admin

---

## Security Rules

Do not commit:

- kubeconfig files
- Dynatrace tokens
- ServiceNow passwords
- Docker Hub tokens
- real Kubernetes Secret YAML files
- generated local evidence files

---

## Required Local Validation Before Automation

Run locally before enabling full automation:

bash -n scripts/run_release_gates.sh

bash -n scripts/run_atlas_drift_check.sh

bash -n scripts/apply_ai_canary.sh

bash -n scripts/apply_ai_rollback.sh

bash -n scripts/validate_istio_traffic_split.sh

bash -n servicenow/create_incident_from_payload.sh

python -m py_compile app/main.py

---

## Automation Readiness Checklist

- [ ] GitHub environment `poc` exists
- [ ] Docker Hub secrets are created
- [ ] KUBECONFIG_B64 secret is created
- [ ] Dynatrace OTLP secrets are created
- [ ] ServiceNow secrets are created
- [ ] Repository variables are created
- [ ] Local script syntax validation passes
- [ ] Release gate workflow is passing
