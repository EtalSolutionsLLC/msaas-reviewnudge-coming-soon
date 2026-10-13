#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT INT TERM

mkdir -p "$fixture/www"
git -C "$fixture" init -q

printf '1.0.0\n' > "$fixture/RELEASE_VERSION"
printf '141\n' > "$fixture/BUILD_NUMBER"

cat > "$fixture/.env" <<'ENV'
APP_SLUG=static-build-fixture
DEPLOY_ENV=dev
RUNTIME_ADAPTER_CODE=static-local
ENV_ROOT=${REPO_ROOT}
SITE_ROOT=${ENV_ROOT}/www
SITE_DIR=${SITE_ROOT}
LOG_DIR=${REPO_ROOT}/logs
ENV

cat > "$fixture/www/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <link href="/assets/site.css" rel="stylesheet">
  <title>Static build fixture</title>
</head>
<body>Static build fixture</body>
<script src="/app.js" type="module"></script>
</html>
HTML

cat > "$fixture/www/app.js" <<'JS'
import { value } from './dependency.js';
const lazyValue = import('./lazy.js?v=old');
console.log(value, lazyValue);
JS

printf 'export const value = 1;\n' > "$fixture/www/dependency.js"
printf 'export default 2;\n' > "$fixture/www/lazy.js"

(
    cd -- "$fixture"
    PORTMASON_SHARE="$root" \
    IN_CONTAINER=true \
    PM_NO_REDIRECT=1 \
    PM_OFFICIAL_BUILD=true \
    PM_SOURCE_COMMIT=0123456789abcdef0123456789abcdef01234567 \
    PM_SOURCE_DIRTY=false \
    PM_DEPLOY_ENV=prd \
    PM_DEPLOYMENT_ID=github-12345-1 \
        "$root/pm-deploy-static" >/dev/null
)

python3 - "$fixture/www" <<'PY'
import json
import sys
from pathlib import Path

site = Path(sys.argv[1])
build = json.loads((site / "build-info.json").read_text(encoding="utf-8"))
deploy = json.loads((site / "deploy-info.json").read_text(encoding="utf-8"))
manifest = json.loads((site / "artifact-manifest.json").read_text(encoding="utf-8"))

assert build["officialBuild"] is True
assert build["sourceCommit"] == "0123456789abcdef0123456789abcdef01234567"
assert build["sourceDirty"] is False
assert build["artifactSha256"]
assert deploy["environment"] == "prd"
assert deploy["deploymentId"] == "github-12345-1"
assert deploy["verification"] == "verified"
assert deploy["artifactSha256"] == build["artifactSha256"]
assert manifest["artifactSha256"] == build["artifactSha256"]
PY

grep -Fq 'site.css?v=141' "$fixture/www/index.html"
grep -Fq 'app.js?v=141' "$fixture/www/index.html"
grep -Fq "from './dependency.js?v=141'" "$fixture/www/app.js"
grep -Fq "import('./lazy.js?v=141')" "$fixture/www/app.js"

printf 'PASS: official static builds are sealed and carry verified deployment metadata\n'
