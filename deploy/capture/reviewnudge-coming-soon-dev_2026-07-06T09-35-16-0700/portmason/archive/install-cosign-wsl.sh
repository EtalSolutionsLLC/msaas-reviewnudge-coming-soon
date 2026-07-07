#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing Cosign for WSL (Linux AMD64)..."

sudo wget -q -O /usr/local/bin/cosign \
  https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64

sudo chmod +x /usr/local/bin/cosign

echo "==> Checking installation:"
cosign version

echo "==> Cosign installed successfully in WSL."
