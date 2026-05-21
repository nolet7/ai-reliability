-- database/seed-data.sql
--
-- Purpose:
-- Adds baseline seed data for the ASR AI Reliability POC.
--
-- This seed data proves the approved model version exists in the database.

INSERT INTO model_versions (
    model_name,
    model_version,
    environment,
    artifact_uri,
    artifact_loaded,
    is_active
)
VALUES (
    'asr-quality-classifier',
    'v1.0.3',
    'poc',
    'local://models/asr-quality-classifier/v1.0.3/model.pkl',
    TRUE,
    TRUE
)
ON CONFLICT (model_name, model_version, environment)
DO UPDATE SET
    artifact_uri = EXCLUDED.artifact_uri,
    artifact_loaded = EXCLUDED.artifact_loaded,
    is_active = EXCLUDED.is_active;
