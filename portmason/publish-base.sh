#!/usr/bin/env bash
# Exit immediately if a command exits with a non-zero status
set -e

: "${PORTMASON_SHARE:="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${0:-}}")" && pwd -P)"}"
. ${PORTMASON_SHARE}/pm-helpers "$@"

# ==============================================================================
# CONFIGURATION
# ==============================================================================
GH_ORG="${GH_DEFAULT_ORG}"
GH_REPO="ops-and-sops"
IMAGE_PATH="ghcr.io/${GH_ORG,,}/${GH_REPO,,}"
GH_PAT=${GITHUB_TOKEN}

# Prompt securely for your GitHub Personal Access Token (PAT)
#echo -n "Enter your GitHub Personal Access Token (with write:packages scope): "
#read -s GH_PAT
#echo ""


if [ -z "$GH_PAT" ]; then
    echo "❌ Error: Token cannot be empty."
    exit 1
fi

GH_USER=$(git config user.username || git config user.name)
if [ -z "$GH_USER" ]; then
    echo -n "Enter your GitHub Username: "
    read GH_USER
fi

# ==============================================================================
# EXECUTION STEPS
# ==============================================================================

echo "🔒 Logging into ghcr.io as $GH_USER..."
echo "$GH_PAT" | docker login ghcr.io -u "$GH_USER" --password-stdin

echo "🏗️ Building the base Docker image from ops/portmason..."
docker build \
  -t "$IMAGE_PATH:latest" \
  -f ops/portmason/Dockerfile \
  ops/portmason

echo "🚀 Pushing the base image to the private GitHub Container Registry..."
docker push "$IMAGE_PATH:latest"

echo "✅ Success! Your private base image is live at: https://github.com"
echo "👉 Remember to go to Package Settings on GitHub to authorize Read Access for your project repos."
