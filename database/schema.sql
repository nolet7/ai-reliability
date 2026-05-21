-- database/schema.sql
--
-- Purpose:
-- Approved PostgreSQL schema for the ASR AI Reliability Incident Automation POC.
--
-- This file is the Git-approved database schema.
-- Atlas will later compare this desired schema against the live PostgreSQL database
-- to detect unauthorized schema drift.
--
-- Main tables:
-- - model_versions: tracks model identity and active model version
-- - prediction_requests: stores inbound prediction request metadata
-- - prediction_results: stores prediction result metadata
-- - incident_audit_log: stores audit and reliability evidence for incident review

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ------------------------------------------------------------
-- Table: model_versions
-- ------------------------------------------------------------
-- Stores model name, model version, environment, and artifact status.
-- This supports model visibility and model-readiness incident triage.

CREATE TABLE IF NOT EXISTS model_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_name TEXT NOT NULL,
    model_version TEXT NOT NULL,
    environment TEXT NOT NULL DEFAULT 'poc',
    artifact_uri TEXT NOT NULL DEFAULT 'local://models/asr-quality-classifier',
    artifact_loaded BOOLEAN NOT NULL DEFAULT TRUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT model_versions_unique_version
        UNIQUE (model_name, model_version, environment),

    CONSTRAINT model_versions_environment_check
        CHECK (environment IN ('poc', 'dev', 'test', 'stage', 'prod'))
);

-- ------------------------------------------------------------
-- Table: prediction_requests
-- ------------------------------------------------------------
-- Stores request-level metadata for each prediction request.
-- This gives SREs request_id and trace_id evidence during incident response.

CREATE TABLE IF NOT EXISTS prediction_requests (
    request_id TEXT PRIMARY KEY,
    trace_id TEXT NOT NULL,
    asset_id TEXT NOT NULL,
    site_id TEXT NOT NULL,
    sensor_score NUMERIC(5,2) NOT NULL,
    service_name TEXT NOT NULL DEFAULT 'asr-ai-quality-service',
    environment TEXT NOT NULL DEFAULT 'poc',
    model_name TEXT NOT NULL DEFAULT 'asr-quality-classifier',
    model_version TEXT NOT NULL DEFAULT 'v1.0.3',
    audit_required BOOLEAN NOT NULL DEFAULT TRUE,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT prediction_requests_sensor_score_check
        CHECK (sensor_score >= 0 AND sensor_score <= 100),

    CONSTRAINT prediction_requests_environment_check
        CHECK (environment IN ('poc', 'dev', 'test', 'stage', 'prod'))
);

-- ------------------------------------------------------------
-- Table: prediction_results
-- ------------------------------------------------------------
-- Stores AI prediction outcome metadata.
-- This supports audit evidence, SLO validation, and incident review.

CREATE TABLE IF NOT EXISTS prediction_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id TEXT NOT NULL,
    quality_risk TEXT NOT NULL,
    confidence NUMERIC(5,2) NOT NULL,
    prediction_status TEXT NOT NULL DEFAULT 'success',
    artifact_loaded BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT prediction_results_request_fk
        FOREIGN KEY (request_id)
        REFERENCES prediction_requests (request_id)
        ON DELETE CASCADE,

    CONSTRAINT prediction_results_request_unique
        UNIQUE (request_id),

    CONSTRAINT prediction_results_quality_risk_check
        CHECK (quality_risk IN ('low', 'medium', 'high')),

    CONSTRAINT prediction_results_confidence_check
        CHECK (confidence >= 0 AND confidence <= 1),

    CONSTRAINT prediction_results_status_check
        CHECK (prediction_status IN ('success', 'failed', 'model_unavailable', 'audit_failed'))
);

-- ------------------------------------------------------------
-- Table: incident_audit_log
-- ------------------------------------------------------------
-- Stores reliability and audit evidence for ServiceNow, Dynatrace, DQL,
-- RCA review, release gates, and schema drift investigation.

CREATE TABLE IF NOT EXISTS incident_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id TEXT,
    trace_id TEXT,
    service_name TEXT NOT NULL DEFAULT 'asr-ai-quality-service',
    environment TEXT NOT NULL DEFAULT 'poc',
    model_name TEXT NOT NULL DEFAULT 'asr-quality-classifier',
    model_version TEXT NOT NULL DEFAULT 'v1.0.3',
    audit_required BOOLEAN NOT NULL DEFAULT TRUE,
    audit_logged BOOLEAN NOT NULL DEFAULT FALSE,
    event_type TEXT NOT NULL,
    event_source TEXT NOT NULL,
    event_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT incident_audit_log_request_fk
        FOREIGN KEY (request_id)
        REFERENCES prediction_requests (request_id)
        ON DELETE SET NULL,

    CONSTRAINT incident_audit_log_environment_check
        CHECK (environment IN ('poc', 'dev', 'test', 'stage', 'prod')),

    CONSTRAINT incident_audit_log_event_type_check
        CHECK (
            event_type IN (
                'prediction_audit',
                'model_health',
                'schema_drift',
                'latency_incident',
                'error_incident',
                'release_gate',
                'rollback'
            )
        )
);

-- ------------------------------------------------------------
-- Indexes
-- ------------------------------------------------------------
-- These indexes support fast incident investigation by request_id, trace_id,
-- model version, environment, and event type.

CREATE INDEX IF NOT EXISTS idx_prediction_requests_trace_id
    ON prediction_requests (trace_id);

CREATE INDEX IF NOT EXISTS idx_prediction_requests_model_version
    ON prediction_requests (model_name, model_version);

CREATE INDEX IF NOT EXISTS idx_prediction_requests_environment
    ON prediction_requests (environment);

CREATE INDEX IF NOT EXISTS idx_prediction_results_quality_risk
    ON prediction_results (quality_risk);

CREATE INDEX IF NOT EXISTS idx_incident_audit_log_request_id
    ON incident_audit_log (request_id);

CREATE INDEX IF NOT EXISTS idx_incident_audit_log_trace_id
    ON incident_audit_log (trace_id);

CREATE INDEX IF NOT EXISTS idx_incident_audit_log_event_type
    ON incident_audit_log (event_type);

CREATE INDEX IF NOT EXISTS idx_incident_audit_log_model_version
    ON incident_audit_log (model_name, model_version);

CREATE INDEX IF NOT EXISTS idx_incident_audit_log_payload_gin
    ON incident_audit_log USING GIN (event_payload);

-- ------------------------------------------------------------
-- Comments
-- ------------------------------------------------------------

COMMENT ON TABLE model_versions IS
'Stores approved AI model metadata used by the ASR reliability POC.';

COMMENT ON TABLE prediction_requests IS
'Stores request-level prediction metadata including request_id and trace_id.';

COMMENT ON TABLE prediction_results IS
'Stores prediction result metadata for audit, SLO, and incident analysis.';

COMMENT ON TABLE incident_audit_log IS
'Stores operational evidence for incidents, release gates, rollback, and drift detection.';
