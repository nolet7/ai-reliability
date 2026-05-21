# ServiceNow Integration User Checklist

## Purpose

This checklist defines what is needed before the AS AI Reliability POC can create ServiceNow incidents.

The integration will later create incidents from:

- Dynatrace runtime problems
- Atlas schema drift detection
- Kubernetes runtime failures
- Release gate failures
- Prediction audit failures

---

## Required ServiceNow Information

ServiceNow instance URL:

Example:
https://your-instance.service-now.com

Required table:

incident

Required API:

ServiceNow Table API

Required method:

POST

Target endpoint format:

/api/now/table/incident

---

## Required Integration User

Create or use a dedicated integration user.

Recommended username:

as.ai.reliability.integration

Recommended role:

itil

Optional roles depending on your ServiceNow setup:

- rest_api_explorer
- web_service_admin
- incident_manager

---

## Required Environment Variables

These values should be stored only in the terminal, CI/CD secret store, Vault, or Kubernetes Secret.

Do not commit them to Git.

SERVICENOW_INSTANCE_URL

SERVICENOW_USERNAME

SERVICENOW_PASSWORD

SERVICENOW_ASSIGNMENT_GROUP

SERVICENOW_DEFAULT_CI

---

## Example Local Environment Variables

Example only:

export SERVICENOW_INSTANCE_URL="https://your-instance.service-now.com"
export SERVICENOW_USERNAME="as.ai.reliability.integration"
export SERVICENOW_PASSWORD="your-password-or-api-secret"
export SERVICENOW_ASSIGNMENT_GROUP="SRE Platform Operations"
export SERVICENOW_DEFAULT_CI="AS AI Quality Service"

---

## Required Incident Fields

short_description

description

assignment_group

cmdb_ci

business_service

category

subcategory

impact

urgency

severity

---

## AS Standard Incident Values

assignment_group:

SRE Platform Operations

cmdb_ci:

AS AI Quality Service

business_service:

AS AI Reliability Platform

category:

Application Reliability

subcategory:

AI Inference Service

impact:

2

urgency:

2

severity:

High

---

## Security Requirements

- Do not hardcode ServiceNow credentials.
- Do not commit passwords into Git.
- Do not print secrets in logs.
- Use a dedicated integration user.
- Rotate credentials after testing.
- Use Vault, CI/CD secrets, or Kubernetes Secrets for production.

---

## Validation Requirements

Before creating real incidents, verify:

- ServiceNow URL is reachable.
- Integration user can authenticate.
- Integration user can create an incident.
- Assignment group exists.
- CI exists or fallback CI is acceptable.
- Incident payload contains Dynatrace or Atlas evidence.
- Created incident can be searched in ServiceNow.
