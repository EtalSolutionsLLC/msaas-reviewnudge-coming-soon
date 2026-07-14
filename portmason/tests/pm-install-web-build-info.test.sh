#!/usr/bin/env bash
set -euo pipefail

PORTMASON_SHARE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/public"
cat > "$fixture/public/index.html" <<'HTML'
<!doctype html>
<html><head><title>Fixture</title></head><body><main>Fixture</main></body></html>
HTML

PORTMASON_SHARE="$PORTMASON_SHARE" \
  "$PORTMASON_SHARE/pm-install-web-build-info" \
  --site-dir "$fixture/public" \
  --entry-file "$fixture/public/index.html" \
  --skip-materialize

PORTMASON_SHARE="$PORTMASON_SHARE" \
  "$PORTMASON_SHARE/pm-install-web-build-info" \
  --site-dir "$fixture/public" \
  --entry-file "$fixture/public/index.html" \
  --skip-materialize

[[ -r "$fixture/public/assets/pm-build-info.js" ]]
[[ -r "$fixture/public/assets/pm-build-info.css" ]]
[[ "$(grep -c 'data-pm-build-info-stylesheet' "$fixture/public/index.html")" -eq 1 ]]
[[ "$(grep -c 'data-pm-build-info-script' "$fixture/public/index.html")" -eq 1 ]]
[[ "$(grep -c 'data-pm-build-info-meta="build"' "$fixture/public/index.html")" -eq 1 ]]
[[ "$(grep -c 'data-pm-build-info-meta="deploy"' "$fixture/public/index.html")" -eq 1 ]]
node --check "$fixture/public/assets/pm-build-info.js"


# Regression: an incomplete deploy snapshot must not block root Build Identity.
materialize_fixture="$(mktemp -d)"
mkdir -p "$materialize_fixture/public" "$materialize_fixture/deploy/prd" "$materialize_fixture/fake-bin"
cat > "$materialize_fixture/public/index.html" <<'HTML'
<!doctype html>
<html><head><title>Materialize fixture</title></head><body><main>Fixture</main></body></html>
HTML
printf '1.2.3\n' > "$materialize_fixture/RELEASE_VERSION"
printf '099\n' > "$materialize_fixture/BUILD_NUMBER"
printf '099\n' > "$materialize_fixture/VERSION"

cat > "$materialize_fixture/fake-bin/pm-version" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

[[ -n "${PM_VERSION_ROOT:-}" ]] || exit 81
[[ ! -d "${PM_VERSION_ROOT}/deploy" ]] || exit 82
[[ "${PM_SOURCE_COMMIT:-}" == fixture-commit ]] || exit 83
[[ "${PM_SOURCE_DIRTY:-}" == false ]] || exit 84

release="$(tr -d '[:space:]' < "${PM_VERSION_ROOT}/RELEASE_VERSION")"
build="$(tr -d '[:space:]' < "${PM_VERSION_ROOT}/BUILD_NUMBER")"
[[ "$(tr -d '[:space:]' < "${PM_VERSION_ROOT}/VERSION")" == "$build" ]] || exit 85

if [[ "${1:-}" == current && "${2:-}" == --json ]]; then
  printf '{"releaseVersion":"%s","buildNumber":"%s"}\n' "$release" "$build"
  exit 0
fi

if [[ "${1:-}" == build && "${2:-}" == materialize && "${3:-}" == --site-dir && -n "${4:-}" ]]; then
  python3 - "$4/build-info.json" "$release" "$build" "${PM_SOURCE_COMMIT}" "${PM_SOURCE_DIRTY}" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(
    json.dumps(
        {
            "releaseVersion": sys.argv[2],
            "buildNumber": sys.argv[3],
            "sourceCommit": sys.argv[4],
            "sourceDirty": sys.argv[5] == "true",
            "officialBuild": False,
        },
        indent=2,
        sort_keys=True,
    ) + "\n",
    encoding="utf-8",
)
PY
  exit 0
fi

exit 86
STUB
chmod +x "$materialize_fixture/fake-bin/pm-version"

PATH="$materialize_fixture/fake-bin:$PATH" \
PM_VERSION_ROOT="$materialize_fixture" \
PM_SOURCE_COMMIT=fixture-commit \
PM_SOURCE_DIRTY=false \
PORTMASON_SHARE="$PORTMASON_SHARE" \
  "$PORTMASON_SHARE/pm-install-web-build-info" \
  --site-dir "$materialize_fixture/public" \
  --entry-file "$materialize_fixture/public/index.html"

python3 - "$materialize_fixture/public/build-info.json" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["releaseVersion"] == "1.2.3"
assert payload["buildNumber"] == "099"
assert payload["sourceCommit"] == "fixture-commit"
assert payload["sourceDirty"] is False
PY
[[ ! -e "$materialize_fixture/deploy/prd/RELEASE_VERSION" ]]
rm -rf "$materialize_fixture"


echo "pm-install-web-build-info test passed"
