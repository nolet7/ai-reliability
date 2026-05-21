#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Phase 9 - Final Demo Runbook + Interview Evidence Pack
#
# Purpose:
#   Generate the final portfolio, demo, resume, and interview
#   evidence pack for the AS AI Reliability POC.
#
# Enterprise value:
#   This converts the technical POC into a recruiter-ready,
#   hiring-manager-ready, and SRE interview-ready story.
# ============================================================

REPORT_ROOT="${REPORT_ROOT:-reports/final-demo-pack}"
RAW_DIR="$REPORT_ROOT/raw"
FINAL_MD="$REPORT_ROOT/as-ai-reliability-final-demo-pack.md"
FINAL_HTML="$REPORT_ROOT/as-ai-reliability-final-demo-pack.html"
FINAL_JSON="$REPORT_ROOT/as-ai-reliability-final-demo-pack.json"

mkdir -p "$RAW_DIR"

PROJECT_NAME="${PROJECT_NAME:-AS AI Reliability POC}"
APP_NAME="${APP_NAME:-as-ai-quality-service}"
NAMESPACE="${NAMESPACE:-ai-reliability-poc}"
ENVIRONMENT="${ENVIRONMENT:-poc}"
EXPECTED_MODEL_VERSION="${EXPECTED_MODEL_VERSION:-v1.0.3}"
ISTIO_INGRESS_IP="${ISTIO_INGRESS_IP:-139.144.255.92}"
APP_LOADBALANCER_IP="${APP_LOADBALANCER_IP:-139.144.255.192}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-nolet7/ai-reliability}"

PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-http://${ISTIO_INGRESS_IP}}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL%/}"

STARTED_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat > "$FINAL_MD" <<EOF
# AS AI Reliability POC — Final Demo, Resume, and Interview Evidence Pack

| Field | Value |
|---|---|
| Project | ${PROJECT_NAME} |
| Application | ${APP_NAME} |
| Namespace | ${NAMESPACE} |
| Environment | ${ENVIRONMENT} |
| Expected Model Version | ${EXPECTED_MODEL_VERSION} |
| Istio Ingress IP | ${ISTIO_INGRESS_IP} |
| App LoadBalancer IP | ${APP_LOADBALANCER_IP} |
| GitHub Repository | ${GITHUB_REPOSITORY} |
| Generated UTC | ${STARTED_UTC} |

---

## 1. Executive Summary

The AS AI Reliability POC demonstrates an enterprise-grade reliability automation platform for AI-backed services. The project shows how an SRE or Platform Engineering team can deploy an AI quality service to Kubernetes, validate database schema drift, integrate with Dynatrace for observability, automate ServiceNow incident creation, and control production traffic with Istio canary and rollback workflows.

This POC is designed to represent a realistic enterprise reliability workflow for AI services where releases must prove:

- Kubernetes deployment health
- AI model version visibility
- Runtime endpoint readiness
- Prediction endpoint functionality
- Observability readiness
- Incident-management integration
- Canary and rollback control
- Evidence generation for audit and release governance

---

## 2. Business Problem

AI services create operational risk when model versions, runtime health, observability, and incident response are not governed together.

A common enterprise problem is:

> The application is deployed, but the platform team cannot prove which model version is serving traffic, whether the prediction path is healthy, whether Dynatrace sees the service, or whether a failed release automatically creates an accountable incident.

This POC solves that problem by connecting:

| Area | Tooling |
|---|---|
| Application runtime | FastAPI |
| Database governance | PostgreSQL + Atlas schema drift detection |
| Container delivery | Docker |
| Kubernetes deployment | LKE Kubernetes |
| Traffic management | Istio |
| Observability | Dynatrace OTLP |
| Incident automation | ServiceNow |
| CI/CD orchestration | GitHub Actions |
| Evidence/audit | Markdown, JSON, CSV, HTML artifacts |

---

## 3. Architecture Story

The platform deploys the AS AI quality service into Kubernetes namespace \`${NAMESPACE}\`. The service exposes live health, ready health, model health, version metadata, prediction, latency simulation, and error simulation endpoints.

The Istio ingress gateway exposes the service externally through:

\`${PUBLIC_BASE_URL}\`

The model-validation endpoints are:

\`\`\`text
/version
/health/model
/predict
\`\`\`

The release workflows validate the service after deployment, confirm the expected model version \`${EXPECTED_MODEL_VERSION}\`, run controlled canary/rollback routing, and create ServiceNow incidents when release or observability gates fail.

---

## 4. Demo Flow for Interview

### Demo Step 1 — Show GitHub Actions automation chain

Open GitHub Actions and show these workflows:

\`\`\`text
00 - Environment Check
02 - Enterprise Deploy to POC Kubernetes
03 - Runtime Release Gate
04 - Dynatrace Validation Gate
05 - ServiceNow Incident on Failure
06 - Canary Rollback Automation
07 - Enterprise POC Evidence Pack
08 - Final Demo Interview Pack
\`\`\`

Explain:

> I built the project so that each phase produces evidence. This is important in enterprise SRE because a release should not just say it succeeded; it should prove runtime health, model version, observability, rollback readiness, and incident accountability.

---

### Demo Step 2 — Validate runtime endpoints

Run:

\`\`\`bash
curl -s ${PUBLIC_BASE_URL}/version
curl -s ${PUBLIC_BASE_URL}/health/model
curl -s -X POST ${PUBLIC_BASE_URL}/predict \\
  -H "Content-Type: application/json" \\
  -H "x-trace-id: demo-interview-run" \\
  -d '{"asset_id":"asset-1001","site_id":"site-asr-poc-001","sensor_score":87.5,"audit_required":true}'
\`\`\`

Expected:

\`\`\`text
/version returns model_version=${EXPECTED_MODEL_VERSION}
/health/model confirms model readiness
/predict returns prediction output with model_version=${EXPECTED_MODEL_VERSION}
\`\`\`

---

### Demo Step 3 — Show Kubernetes runtime state

Run:

\`\`\`bash
kubectl config use-context lke605802-ctx

kubectl -n ${NAMESPACE} get deploy,pods,svc -o wide
kubectl -n ${NAMESPACE} get gateway,virtualservice,destinationrule
kubectl -n ${NAMESPACE} get pods --show-labels
\`\`\`

Explain:

> I validate both Kubernetes health and Istio routing resources because a pod can be healthy but the route can still be broken. In the POC, I learned this directly when /model returned 404 because the actual AI model version endpoint was /version.

---

### Demo Step 4 — Show rollback workflow

Open:

\`\`\`text
GitHub Actions → 06 - Canary Rollback Automation
\`\`\`

Run rollback:

\`\`\`text
mode: rollback
validation_requests: 30
expected_primary_model_version: ${EXPECTED_MODEL_VERSION}
\`\`\`

Expected:

\`\`\`text
v1 Weight = 100
v2 Weight = 0
HTTP Failures = 0
Primary Version Count = 30
Final Status = passed
\`\`\`

Explain:

> The rollback workflow is not just applying Istio YAML. It validates that traffic actually returns the expected model version after rollback.

---

### Demo Step 5 — Show ServiceNow incident automation

Open:

\`\`\`text
GitHub Actions → 05 - ServiceNow Incident on Failure
\`\`\`

Explain:

> When a release gate or observability gate fails, the workflow creates or updates a ServiceNow incident using correlation_id duplicate detection. This prevents alert noise and keeps one accountable incident per app, environment, and workflow failure.

Key point:

\`\`\`text
Repeated failures update the same active incident instead of creating duplicates.
\`\`\`

---

### Demo Step 6 — Show Dynatrace validation

Open:

\`\`\`text
GitHub Actions → 04 - Dynatrace Validation Gate
\`\`\`

Explain:

> This gate validates that the AI service is visible in Dynatrace before the release is accepted. It checks API connectivity, service/entity discovery, metrics access, and open problems.

---

## 5. Production Failure Scenario

### Scenario

A new AI model version is deployed to Kubernetes. The Kubernetes rollout succeeds, but the runtime release gate fails because the model version endpoint does not return the expected value.

### Impact

- Wrong model may serve production traffic
- Quality predictions may be unreliable
- Audit trail may show an unapproved model version
- Release should not be promoted

### Automated Response

1. GitHub Actions runtime gate fails.
2. ServiceNow incident automation creates or updates an incident.
3. SRE reviews evidence artifact.
4. Istio rollback workflow routes 100% traffic to the stable version.
5. Dynatrace is checked for service health, latency, traces, and open problems.
6. RCA is documented and release governance updated.

---

## 6. Resume Bullet Points

### Senior SRE / Platform Engineer Bullet

- Built an enterprise-grade AI reliability automation POC using FastAPI, PostgreSQL, Atlas, Docker, Kubernetes, Istio, Dynatrace OTLP, ServiceNow, and GitHub Actions to validate AI model versioning, runtime readiness, observability, incident automation, canary release, rollback, and audit evidence generation across a Kubernetes-based platform.

### Incident Management Bullet

- Automated ServiceNow incident creation and duplicate detection for failed AI release gates using GitHub Actions workflow triggers, correlation IDs, severity/impact/urgency mapping, assignment-group routing, GitHub evidence links, and operational work notes to reduce manual triage and improve incident accountability.

### Observability Bullet

- Integrated Dynatrace validation into AI release automation by verifying service/entity discovery, metric API access, open-problem status, and observability evidence before accepting a runtime release, strengthening SRE release governance and production support readiness.

### Kubernetes / Istio Bullet

- Implemented Istio-based canary and rollback automation for an AI quality service, validating traffic routing with runtime model-version checks and producing release artifacts that prove rollback success rather than relying only on configuration changes.

### CI/CD Governance Bullet

- Designed GitHub Actions release gates that generate Markdown, JSON, CSV, HTML, and raw Kubernetes/Istio evidence artifacts, enabling auditable CI/CD governance for AI reliability services.

---

## 7. STAR Interview Answers

### STAR 1 — Tell me about a reliability automation project you built.

**Situation:**  
An AI-backed service needed a reliable release process that could prove the deployed model version, runtime health, observability, and incident response readiness.

**Task:**  
I needed to build a POC that demonstrated enterprise SRE release governance for AI services using Kubernetes, Dynatrace, ServiceNow, and GitHub Actions.

**Action:**  
I built a FastAPI AI quality service with health, model-readiness, version, and prediction endpoints. I containerized it with Docker, deployed it to Kubernetes, added Istio traffic routing, connected telemetry to Dynatrace, and built GitHub Actions workflows for deployment, runtime gates, Dynatrace validation, ServiceNow incidents, canary routing, rollback, and evidence generation.

**Result:**  
The POC produced a full automated release chain with audit artifacts. It could detect runtime failures, validate model version \`${EXPECTED_MODEL_VERSION}\`, trigger ServiceNow incidents, and roll traffic back through Istio with evidence showing whether rollback actually worked.

---

### STAR 2 — Describe a time you found and fixed a release-gate issue.

**Situation:**  
During the canary/rollback workflow, the rollback configuration applied successfully, but runtime validation failed with 30 HTTP failures.

**Task:**  
I needed to determine whether the failure was Kubernetes, Istio, service routing, or the AI application endpoint.

**Action:**  
I tested the service externally and discovered that Istio was routing correctly, but the workflow was validating the wrong path. The script used \`/model\`, which returned 404, while the actual model version endpoint was \`/version\`, and model health was available at \`/health/model\`. I updated the workflow to use \`/version\` for model-version validation and \`/health/model\` for AI model readiness.

**Result:**  
The fix converted a false release failure into a valid AI model reliability gate. It also improved the enterprise design because model version and model health were validated separately.

---

### STAR 3 — How did you integrate incident management?

**Situation:**  
Failed release gates can be missed if they only appear in CI/CD logs.

**Task:**  
I needed failed runtime or observability gates to become accountable operational work.

**Action:**  
I created a ServiceNow incident automation workflow triggered by failed GitHub Actions workflows. The automation created or updated incidents using correlation IDs, added evidence links, mapped impact and urgency, supported assignment groups, and prevented duplicate incident noise.

**Result:**  
Release failures became traceable operational incidents with work notes, GitHub evidence, app context, namespace, environment, commit SHA, and workflow details.

---

### STAR 4 — How did you prove rollback worked?

**Situation:**  
In many systems, teams apply rollback configuration but do not prove that live traffic actually returned to the stable version.

**Task:**  
I needed to prove rollback at runtime.

**Action:**  
I built a GitHub Actions rollback workflow that applies Istio routing with v1 at 100% and v2 at 0%, then sends validation requests to the public endpoint and checks that responses return the expected stable model version.

**Result:**  
Rollback success became measurable. The workflow reports HTTP failures, primary model-version count, traffic mode, route weights, and raw evidence artifacts.

---

### STAR 5 — How did Dynatrace fit into the release process?

**Situation:**  
A release can pass Kubernetes checks but still lack observability, making production incidents difficult to troubleshoot.

**Task:**  
I needed to ensure the service was visible in Dynatrace before considering the release complete.

**Action:**  
I created a Dynatrace validation gate that checks API connectivity, service/entity discovery, metric query access, and open problem status for the AI quality service.

**Result:**  
The release process validates not only application health but also operational visibility, improving incident readiness and reducing blind spots.

---

## 8. Hiring Manager Talk Track

Use this concise explanation:

> This project demonstrates how I approach SRE for AI services. I do not treat deployment success as the final signal. I validate runtime health, model version, prediction behavior, observability, incident routing, and rollback readiness. The workflows generate evidence artifacts so the release is auditable and repeatable. The most important part is that failures are not silent — failed gates create or update ServiceNow incidents and rollback is validated by real runtime responses.

---

## 9. Final Demo Commands

\`\`\`bash
curl -s ${PUBLIC_BASE_URL}/version

curl -s ${PUBLIC_BASE_URL}/health/model

curl -s -X POST ${PUBLIC_BASE_URL}/predict \\
  -H "Content-Type: application/json" \\
  -H "x-trace-id: final-demo" \\
  -d '{"asset_id":"asset-1001","site_id":"site-asr-poc-001","sensor_score":87.5,"audit_required":true}'

kubectl -n ${NAMESPACE} get deploy,pods,svc -o wide

kubectl -n ${NAMESPACE} get gateway,virtualservice,destinationrule
\`\`\`

---

## 10. Final Project Status Checklist

| Area | Status |
|---|---|
| FastAPI AI service | Completed |
| PostgreSQL + Atlas drift detection | Completed |
| Docker build/push | Completed |
| Kubernetes deployment | Completed |
| Dynatrace OTLP integration | Completed |
| ServiceNow incident automation | Completed |
| Istio install and sidecar injection | Completed |
| Canary routing | Completed |
| Rollback routing | Completed |
| Runtime release gate | Completed |
| Enterprise evidence reports | Completed |
| Final interview/demo pack | Completed |

EOF

python3 - "$FINAL_MD" "$FINAL_HTML" <<'PY'
import html
import json
import sys
from pathlib import Path

md_path = Path(sys.argv[1])
html_path = Path(sys.argv[2])

content = md_path.read_text(encoding="utf-8")

html_content = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>AS AI Reliability Final Demo Pack</title>
  <style>
    body {{
      font-family: Arial, sans-serif;
      margin: 40px;
      line-height: 1.55;
      color: #1f2937;
    }}
    h1, h2, h3 {{
      color: #111827;
    }}
    pre {{
      background: #f3f4f6;
      padding: 16px;
      border-radius: 8px;
      overflow-x: auto;
      white-space: pre-wrap;
    }}
  </style>
</head>
<body>
<pre>{html.escape(content)}</pre>
</body>
</html>
"""

html_path.write_text(html_content, encoding="utf-8")
PY

cat > "$FINAL_JSON" <<EOF
{
  "phase": "Phase 9 - Final Demo Runbook and Interview Evidence",
  "project": "${PROJECT_NAME}",
  "application": "${APP_NAME}",
  "namespace": "${NAMESPACE}",
  "environment": "${ENVIRONMENT}",
  "expected_model_version": "${EXPECTED_MODEL_VERSION}",
  "public_base_url": "${PUBLIC_BASE_URL}",
  "github_repository": "${GITHUB_REPOSITORY}",
  "generated_utc": "${STARTED_UTC}",
  "outputs": {
    "markdown": "${FINAL_MD}",
    "html": "${FINAL_HTML}",
    "json": "${FINAL_JSON}"
  }
}
EOF

echo
echo "Final demo/interview pack generated:"
echo "$FINAL_MD"
echo "$FINAL_HTML"
echo "$FINAL_JSON"
