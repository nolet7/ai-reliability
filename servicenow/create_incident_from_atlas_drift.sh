#!/usr/bin/env bash

# servicenow/create_incident_from_atlas_drift.sh
#
# Purpose:
# Creates a ServiceNow incident from Atlas schema drift evidence.
#
# Default behavior:
# Uses DRY_RUN=true unless you explicitly set DRY_RUN=false.

set -euo pipefail

PAYLOAD_FILE="servicenow/sample-atlas-drift-incident-payload.json"

./servicenow/create_incident_from_payload.sh "${PAYLOAD_FILE}"
