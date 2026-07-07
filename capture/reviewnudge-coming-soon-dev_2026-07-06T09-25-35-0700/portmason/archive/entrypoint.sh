#!/usr/bin/env bash
set -euo pipefail

: "${CUR_SCRIPT:=$(basename "${BASH_SOURCE[0]}")}"
export CUR_SCRIPT

# -----------------------------------------------------------------------------
# repo-backup runtime entrypoint
#
# Expects:
#   RUNTIME_ARTIFACT : gs://... or https://... or absolute local path
#
# Optional:
#   entrypoint               : path to executable within extracted app root
#                             default: /opt/app/backup-github-repos
#
# Fix 1 (emulation): If host gcloud config is mounted read-only at /host-gcloud,
# copy it into a writable config dir (default /gcloud/config) so gcloud can
# create credentials.db, logs, etc.
# -----------------------------------------------------------------------------

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

setup_gcloud_runtime() {
  # Make gcloud behave well in read-only container environments.
  # - Never prompt
  # - Ensure config/log dirs exist and are writable when possible
  # - If /host-gcloud is mounted (RO), copy it into writable CLOUDSDK_CONFIG
  #
  # IMPORTANT: This function must never hard-fail; it should only log warnings.

  export CLOUDSDK_CORE_DISABLE_PROMPTS="${CLOUDSDK_CORE_DISABLE_PROMPTS:-1}"
  export HOME="${HOME:-/tmp}"

  # Prefer caller-provided paths; otherwise choose sensible writable defaults.
  export CLOUDSDK_CONFIG="${CLOUDSDK_CONFIG:-/gcloud/config}"
  export CLOUDSDK_LOG_DIR="${CLOUDSDK_LOG_DIR:-/gcloud/logs}"

  # Try to ensure dirs exist (ignore failures).
  mkdir -p "$HOME" >/dev/null 2>&1 || true
  mkdir -p "$CLOUDSDK_CONFIG" >/dev/null 2>&1 || true
  mkdir -p "$CLOUDSDK_LOG_DIR" >/dev/null 2>&1 || true

  # If host config is provided read-only, copy into writable config dir.
  # This avoids gcloud trying to write to the RO mount (credentials.db, lock files, etc.)
  if [[ -d "/host-gcloud" ]]; then
    # Only attempt copy if destination seems writable.
    if [[ -w "$CLOUDSDK_CONFIG" ]]; then
      # Copy quietly; tolerate partial copies. Preserve attributes when possible.
      cp -a /host-gcloud/. "$CLOUDSDK_CONFIG/" >/dev/null 2>&1 || cp -r /host-gcloud/. "$CLOUDSDK_CONFIG/" >/dev/null 2>&1 || true
      log "gcloud config: copied /host-gcloud -> ${CLOUDSDK_CONFIG} (best-effort)"
    else
      log "WARNING: gcloud config dir not writable: ${CLOUDSDK_CONFIG} (skipping /host-gcloud copy)"
    fi
  fi
}

fetch_to() {
  # fetch_to <src> <dst>
  # Supports:
  #   - gs://... via gcloud storage cp
  #   - http(s)://... via curl
  #   - local absolute path
  local src="${1:?}"
  local dst="${2:?}"

  if [[ "$src" == gs://* ]]; then
    command -v gcloud >/dev/null 2>&1 || die "gcloud required to fetch: $src"
    # Use stderr for gcloud output; keep it quiet otherwise
    gcloud storage cp "$src" "$dst" >/dev/null
  elif [[ "$src" == http://* || "$src" == https://* ]]; then
    command -v curl >/dev/null 2>&1 || die "curl required to fetch: $src"
    curl -fsSL "$src" -o "$dst"
  else
    [[ "$src" == /* ]] || die "Local artifact paths must be absolute: $src"
    [[ -f "$src" ]] || die "Artifact not found: $src"
    cp -f "$src" "$dst"
  fi
}

safe_extract_tgz() {
  # safe_extract_tgz <tgz> <dest_dir> <label>
  local tgz="${1:?}"
  local dest="${2:-/opt}"
  local label="${3:-}"

  [[ "$tgz" == *.tgz || "$tgz" == *.tar.gz ]] || die "${label} must be .tgz or .tar.gz (got: $tgz)"

  # Basic guardrail: never allow extraction targets that could wipe critical roots.
  [[ "$dest" != "/" ]] || die "Refusing to extract to /"
  [[ "$dest" != "/opt" ]] || die "Refusing to extract to /opt (target must be /opt/<name>)"

  rm -rf "$dest"
  mkdir -p "$dest"

  # Prevent path traversal (absolute paths or ..)
  if tar -tzf "$tgz" | awk '
    BEGIN{bad=0}
    /^\//{bad=1}
    /(^|\/)\.\.(\/|$)/{bad=1}
    END{exit bad}
  '; then
    :
  else
    die "${label} contains unsafe paths (absolute or ..)"
  fi

  tar -xzf "$tgz" -C "$dest"
}

main() {
  : "${RUNTIME_ARTIFACT:?}"

  # Fix 1 wiring: make gcloud usable before any gs:// fetch
  setup_gcloud_runtime

  local ts runtime_tgz
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  runtime_tgz="/tmp/runtime.${ts}.tgz"

  log "Fetching artifacts..."
  fetch_to "$RUNTIME_ARTIFACT" "$runtime_tgz"

  log "Extracting runtime..."
  local base="/source"
  safe_extract_tgz "$runtime_tgz" "${base}" ""

  # Set environment variables for use inside the container by entrypoint script
  export APP_ROOT="${base}/app"
  export PORTMASON_SHARE="${base}/portmason"
  export SCRIPT_DIR="${APP_ROOT}"

  log "Directory hierarchy inside container:"
  log "$(cd "$base" && ls -laR)"

  : "${entrypoint:=${APP_ROOT}/backup-github-repos}"
  [[ -x "${entrypoint}" ]] || die "Script not found/executable at: ${entrypoint}"

  log "Executing backup entrypoint: ${entrypoint}"
  exec "${entrypoint}"
}

main "$@"
