# database/atlas.hcl
#
# Purpose:
# Atlas configuration for ASR AI Reliability POC schema drift detection.
#
# Important:
# Atlas free/local mode blocks extension management in schema diff.
# Therefore, this config uses database/schema-atlas.sql, which excludes:
# CREATE EXTENSION IF NOT EXISTS pgcrypto;
#
# The pgcrypto extension is installed manually in both:
# - live database: asr_ai_poc
# - dev database: dev

env "poc" {
  src = "file://database/schema-atlas.sql"

  url = "postgres://asr_user:asr_password@asr-ai-postgres-poc:5432/asr_ai_poc?sslmode=disable"

  dev = "postgres://asr_user:asr_password@asr-ai-atlas-dev-postgres:5432/dev?sslmode=disable"
}
