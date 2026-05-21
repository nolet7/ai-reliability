#!/usr/bin/env bash

# servicenow/test_servicenow_auth.sh
#
# Purpose:
# Safely tests ServiceNow authentication and incident table access.
#
# This script does NOT create an incident.
# It sends a GET request to the incident table with sysparm_limit=1.
#
# Windows/Git Bash note:
# --ssl-no-revoke is used for this POC because Windows Schannel may fail
# certificate revocation checks for developer ServiceNow instances.
# Do not use this bypass as a production security standard.

set -euo pipefail

: "${SERVICENOW_INSTANCE_URL:?SERVICENOW_INSTANCE_URL is required}"
: "${SERVICENOW_USERNAME:?SERVICENOW_USERNAME is required}"
: "${SERVICENOW_PASSWORD:?SERVICENOW_PASSWORD is required}"

SERVICENOW_INSTANCE_URL="${SERVICENOW_INSTANCE_URL%/}"
TEST_URL="${SERVICENOW_INSTANCE_URL}/api/now/table/incident?sysparm_limit=1"

echo "============================================================"
echo "AS AI Reliability POC - ServiceNow Auth Test"
echo "============================================================"
echo "Instance: ${SERVICENOW_INSTANCE_URL}"
echo "Username: ${SERVICENOW_USERNAME}"
echo "Password set: yes"
echo "API test URL: ${TEST_URL}"
echo

HTTP_RESPONSE_FILE="/tmp/as_servicenow_auth_response.json"
HTTP_STATUS_FILE="/tmp/as_servicenow_auth_status.txt"
CURL_ERROR_FILE="/tmp/as_servicenow_curl_error.txt"

echo "Sending safe GET request to ServiceNow..."
echo

set +e
curl -sS \
  --ssl-no-revoke \
  --connect-timeout 20 \
  --max-time 60 \
  -u "${SERVICENOW_USERNAME}:${SERVICENOW_PASSWORD}" \
  -H "Accept: application/json" \
  -X GET \
  "${TEST_URL}" \
  -o "${HTTP_RESPONSE_FILE}" \
  -w "%{http_code}" > "${HTTP_STATUS_FILE}" \
  2> "${CURL_ERROR_FILE}"

CURL_EXIT_CODE=$?
set -e

echo "curl exit code: ${CURL_EXIT_CODE}"

if [ -s "${CURL_ERROR_FILE}" ]; then
  echo
  echo "curl error output:"
  cat "${CURL_ERROR_FILE}"
fi

if [ ! -s "${HTTP_STATUS_FILE}" ]; then
  echo
  echo "No HTTP status was returned."
  exit 1
fi

HTTP_STATUS="$(cat "${HTTP_STATUS_FILE}")"

echo
echo "HTTP status: ${HTTP_STATUS}"
echo

if [ -s "${HTTP_RESPONSE_FILE}" ]; then
  echo "Response preview:"
  cat "${HTTP_RESPONSE_FILE}" | python -m json.tool || cat "${HTTP_RESPONSE_FILE}"
else
  echo "Response body is empty."
fi

echo

if [ "${CURL_EXIT_CODE}" -ne 0 ]; then
  echo "curl failed before completing the request."
  exit 1
fi

if [ "${HTTP_STATUS}" != "200" ]; then
  echo "ServiceNow authentication or incident table access failed."
  echo
  echo "Common causes:"
  echo "- 401: username/password is wrong"
  echo "- 403: user lacks incident table/API permissions"
  echo "- 404: wrong instance URL or endpoint"
  echo "- 000: network, DNS, TLS, timeout, or sleeping developer instance"
  exit 1
fi

echo "============================================================"
echo "ServiceNow authentication test passed."
echo "============================================================"

rm -f "${HTTP_RESPONSE_FILE}" "${HTTP_STATUS_FILE}" "${CURL_ERROR_FILE}"
