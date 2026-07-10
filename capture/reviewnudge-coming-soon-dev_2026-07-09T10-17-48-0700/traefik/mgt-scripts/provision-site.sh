#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: provision-site.sh /abs/path/to/site-dir [<compose-file>]" >&2
  exit 1
fi

SITE_DIR="$1"
COMPOSE_FILE="${2:-docker-compose.yml}"

TRAEFIK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="$TRAEFIK_DIR/certs"
DYN_DIR="$TRAEFIK_DIR/dynamic"
CERTS_OUT="$TRAEFIK_DIR/out-certs"

if ! command -v sys-gen-sslcert >/dev/null 2>&1; then
  echo "ERROR: sys-gen-sslcert not found in PATH." >&2
  exit 1
fi

mkdir -p "$CERT_DIR" "$CERTS_OUT"

pushd "$SITE_DIR" >/dev/null

# Render the effective compose config so labels are visible
CONFIG_OUT="$(mktemp)"
docker compose -f "$COMPOSE_FILE" config > "$CONFIG_OUT"

# Try to extract the Host() from any HTTPS router label
# Looking for e.g. traefik.http.routers.*-secure.rule=Host(`example.localtest.me`)
CN="$(grep -Eo "traefik\.http\.routers\.[^=]*-secure\.rule=Host\(\`[^\\\`]+\`\)" "$CONFIG_OUT" \
     | sed -E "s/.*Host\(\`([^\`]+)\`\).*/\1/" \
     | head -n1 || true)"

if [[ -n "$CN" ]]; then
  echo "==> HTTPS router detected. Issuing cert for CN=$CN"
  sys-gen-sslcert -o "$CERT_DIR" --cn "$CN" -f

  STEM="$(echo "$CN" | sed 's/\*/wildcard/g; s/[ /]/_/g; s/\//_/g')"
  FULLCHAIN="$CERT_DIR/$STEM.fullchain.crt"
  KEY="$CERT_DIR/$STEM.key"
  if [[ ! -f "$FULLCHAIN" || ! -f "$KEY" ]]; then
    echo "ERROR: Expected $FULLCHAIN and/or $KEY not found."
    rm -f "$CONFIG_OUT"
    exit 1
  fi

  SITE_CERT_YML="$CERTS_OUT/$STEM.yml"
  cat > "$SITE_CERT_YML" <<YAML
tls:
  certificates:
    - certFile: /certs/$(basename "$FULLCHAIN")
      keyFile:  /certs/$(basename "$KEY")
YAML

  # Trigger Traefik reload
  touch "$DYN_DIR/certificates.yml" 2>/dev/null || touch "$DYN_DIR/dashboard.yml"
else
  echo "==> No HTTPS router found; skipping cert issuance."
fi

echo "==> Bringing site up: $SITE_DIR"
docker compose -f "$COMPOSE_FILE" up -d

rm -f "$CONFIG_OUT"
popd >/dev/null
