#!/usr/bin/env bash
set -Eeuo pipefail

APP_SCRIPT_URL='https://script.google.com/macros/s/AKfycbwFWlO31J_Oh5aRoBa9QVNbhCGbOq-pxgqKiZavkY-A61dFHoNA1v4KPNTaUcIDtacy/exec'
KNOWN_TRACE_ID='b268ed8e-15aa-4b98-af35-6157a1ca37bd'
TEST_EMAIL="${1:-}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'ERROR: Required command not found: %s\n' "$1" >&2
    exit 1
  }
}

print_response() {
  local label="$1"
  local response_file="$2"
  local status_code="$3"

  printf '\n=== %s ===\n' "$label"
  printf 'HTTP status: %s\n' "$status_code"

  if jq empty "$response_file" >/dev/null 2>&1; then
    jq . "$response_file"
  else
    cat "$response_file"
    printf '\n'
  fi
}

get_json() {
  local label="$1"
  local output_file="$2"
  shift 2

  local status_code
  status_code="$(
    curl \
      --silent \
      --show-error \
      --location \
      --proto-redir '=https' \
      --output "$output_file" \
      --write-out '%{http_code}' \
      "$@"
  )"

  print_response "$label" "$output_file" "$status_code"
}

post_json() {
  local label="$1"
  local payload="$2"
  local output_file="$3"

  local status_code

  # Do not add --request POST here.
  # --data-binary makes the initial request a POST, while curl may correctly
  # follow Google's ContentService redirect as a GET.
  status_code="$(
    curl \
      --silent \
      --show-error \
      --location \
      --proto-redir '=https' \
      --output "$output_file" \
      --write-out '%{http_code}' \
      --header 'Content-Type: text/plain;charset=utf-8' \
      --data-binary "$payload" \
      "$APP_SCRIPT_URL"
  )"

  print_response "$label" "$output_file" "$status_code"
}

require_command curl
require_command jq

if [[ -z "$TEST_EMAIL" ]]; then
  printf 'Usage: %s test-email@example.com\n' "$0" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

HEALTH_FILE="$TMP_DIR/health.json"
KNOWN_STATUS_FILE="$TMP_DIR/known-status.json"
POST_FILE="$TMP_DIR/post.json"
STATUS_FILE="$TMP_DIR/status.json"

get_json \
  '1. Service availability' \
  "$HEALTH_FILE" \
  "$APP_SCRIPT_URL"

if jq -e '
  .ok == true
  and .service == "reviewnudge-waitlist"
  and .audit == true
  and .verification == true
' "$HEALTH_FILE" >/dev/null 2>&1; then
  printf '\nDEPLOYMENT CHECK: New audited Apps Script is active.\n'
else
  printf '\nDEPLOYMENT CHECK: The URL is not serving the new audited Apps Script.\n'
  printf 'Expected service="reviewnudge-waitlist", audit=true, verification=true.\n'
  printf 'Update Code.gs, then edit the existing web-app deployment to use a new version.\n'
fi

get_json \
  '2. Existing trace status' \
  "$KNOWN_STATUS_FILE" \
  --get \
  --data-urlencode 'action=status' \
  --data-urlencode "traceId=$KNOWN_TRACE_ID" \
  "$APP_SCRIPT_URL"

TRACE_ID="manual-$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}"

PAYLOAD="$(
  jq -nc \
    --arg email "$TEST_EMAIL" \
    --arg traceId "$TRACE_ID" \
    --arg submittedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      email: $email,
      traceId: $traceId,
      source: "manual-app-script-test",
      page: "independent-shell-test",
      referrer: "",
      userAgent: "curl",
      submittedAt: $submittedAt
    }'
)"

printf '\nTrace ID for this test: %s\n' "$TRACE_ID"

post_json \
  '3. Independent signup submission' \
  "$PAYLOAD" \
  "$POST_FILE"

sleep 2

get_json \
  '4. Submitted trace status' \
  "$STATUS_FILE" \
  --get \
  --data-urlencode 'action=status' \
  --data-urlencode "traceId=$TRACE_ID" \
  "$APP_SCRIPT_URL"

printf '\n=== Final result ===\n'

if jq -e '.recorded == true' "$STATUS_FILE" >/dev/null 2>&1; then
  printf 'PASS: Google confirmed the spreadsheet row.\n'
  printf 'Trace ID: %s\n' "$TRACE_ID"
  exit 0
fi

if jq -e '
  .service == "func-reviewnudge-waitlist"
  or (.audit != true)
  or (.verification != true)
' "$HEALTH_FILE" >/dev/null 2>&1; then
  printf 'FAIL: The configured URL is still serving the legacy Apps Script deployment.\n'
  printf 'Deploy the Build 082 apps-script/Code.gs as a new web-app version, then rerun this test.\n'
  printf 'Trace ID: %s\n' "$TRACE_ID"
  exit 2
fi

printf 'FAIL: The audited deployment is active, but the row was not confirmed.\n'
printf 'Inspect the WaitlistAudit sheet and Apps Script Executions for trace ID:\n%s\n' "$TRACE_ID"
exit 3
