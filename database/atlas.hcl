# database/atlas.hcl
#
# Purpose:
# Atlas configuration for AS AI Reliability POC schema drift detection.
#
# Important:
# Atlas free/local mode blocks extension management in schema diff.
# Therefore, this config uses database/schema-atlas.sql, which excludes:
# CREATE EXTENSION IF NOT EXISTS pgcrypto;
#
# The pgcrypto extension is installed manually in both:
# - live database: as_ai_poc
# - dev database: dev

env "poc" {
  src = "file://database/schema-atlas.sql"

  url = "postgres://as_user:as_password@as-ai-postgres-poc:5432/as_ai_poc?sslmode=disable"

  dev = "postgres://as_user:as_password@as-ai-atlas-dev-postgres:5432/dev?sslmode=disable"
}
