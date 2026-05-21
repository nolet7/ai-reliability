# Database Reliability Layer

## Purpose

This folder contains the PostgreSQL database schema and Atlas drift detection files for the AS AI Reliability Incident Automation POC.

The database supports:

- Model visibility
- Prediction request tracking
- Prediction result tracking
- Prediction audit evidence
- ServiceNow incident evidence
- Atlas schema drift detection

---

## Files

| File | Purpose |
|---|---|
| `schema.sql` | Git-approved PostgreSQL schema |
| `seed-data.sql` | Baseline model version seed data |
| `drift-simulation.sql` | Unauthorized schema change used to test drift detection |
| `atlas.hcl` | Atlas configuration file |
| `README.md` | Database layer documentation |

---

## Main Tables

| Table | Purpose |
|---|---|
| `model_versions` | Tracks model name, version, artifact status, and environment |
| `prediction_requests` | Stores inbound prediction request metadata |
| `prediction_results` | Stores prediction output metadata |
| `incident_audit_log` | Stores operational evidence for incidents and release gates |

---

## Why This Matters

Database schema drift can cause application failures, failed deployments, broken queries, missing audit evidence, and production incidents.

Atlas will later compare the approved Git schema:

```text
database/schema.sql
against the live PostgreSQL database:

as_ai_poc

If the live database is changed outside the approved Git process, Atlas will detect drift and we will generate drift evidence for ServiceNow.
