#!/usr/bin/env bash

# servicenow/create_incident_from_dynatrace.sh
#
# Purpose:
# Creates a ServiceNow incident from AS Dynatrace runtime evidence.

set -euo pipefail

PAYLOAD_FILE="servicenow/sample-dynatrace-incident-payload.json"

./servicenow/create_incident_from_payload.sh "${PAYLOAD_FILE}"
