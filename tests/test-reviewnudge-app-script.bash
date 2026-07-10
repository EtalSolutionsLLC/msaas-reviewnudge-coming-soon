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

request_get() {
  local label="$1"
  shift

  local response_file
  response_file="$(mktemp)"

  local status_code
  status_code="$(
    curl \
      --silent \
      --show-error \
      --location \
      --output "$response_file" \
      --write-out '%{http_code}' \
      "$@"
  )"

  print_response "$label" "$response_file" "$status_code"
  rm -f "$response_file"
}

request_post() {
  local label="$1"
  local payload="$2"

  local response_file
  response_file="$(mktemp)"

  local status_code
  status_code="$(
    curl \
      --silent \
      --show-error \
      --location \
      --output "$response_file" \
      --write-out '%{http_code}' \
      --request POST \
      --header 'Content-Type: text/plain;charset=utf-8' \
      --data-binary "$payload" \
      "$APP_SCRIPT_URL"
  )"

  print_response "$label" "$response_file" "$status_code"

  if [[ "$status_code" == "405" ]]; then
    printf '\nDIAGNOSIS: This deployed endpoint does not accept POST requests.\n'
    printf 'The URL is likely pointing to an older or different deployment than the new waitlist Apps Script code.\n'
  fi

  rm -f "$response_file"
}

require_command curl
require_command jq

if [[ -z "$TEST_EMAIL" ]]; then
  printf 'Usage: %s test-email@example.com\n' "$0" >&2
  exit 1
fi

request_get \
  '1. Service availability' \
  "$APP_SCRIPT_URL"

request_get \
  '2. Existing trace status' \
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

request_post \
  '3. Independent signup submission' \
  "$PAYLOAD"

sleep 2

request_get \
  '4. Submitted trace status' \
  --get \
  --data-urlencode 'action=status' \
  --data-urlencode "traceId=$TRACE_ID" \
  "$APP_SCRIPT_URL"

printf '\nSearch the Waitlist and WaitlistAudit sheets for:\n%s\n' "$TRACE_ID"
