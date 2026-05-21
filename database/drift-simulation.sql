-- database/drift-simulation.sql
--
-- Purpose:
-- Simulates unauthorized PostgreSQL schema drift for the ASR AI Reliability POC.
--
-- This file intentionally changes the live database outside the approved Git schema.
-- Atlas should detect this drift because database/schema-atlas.sql does not contain
-- unauthorized_debug_column.
--
-- Scenario:
-- A developer or DBA manually adds a debug column directly in production or POC
-- without a pull request, migration review, release gate, or ServiceNow change record.

ALTER TABLE prediction_requests
ADD COLUMN unauthorized_debug_column TEXT;
