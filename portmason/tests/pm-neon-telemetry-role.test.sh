#!/usr/bin/env bash
set -euo pipefail

source_dir=/home/davidomer/code/ops-and-sops/ops/portmason
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
mkdir -p "$temp_dir/share" "$temp_dir/bin"
cp "$source_dir/pm-helpers-neon" "$temp_dir/share/"

printf '%s\n' \
  'log() { printf "%s\n" "$*" >>"${TEST_LOG:?}"; }' \
  'die() { log ERROR "$*"; return "${2:-1}"; }' \
  'env_init_set() { printf -v "$1" "%s" "${2-}"; export "$1"; }' \
  'pm_secret_resolve_value() { printf -v "$1" "%s" "${3-}"; }' \
  >"$temp_dir/share/pm-helpers"

cat >"$temp_dir/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
method=GET output="" url="" data=""
while ((${#})); do
  case "$1" in
    --request) method="$2"; shift ;;
    --output) output="$2"; shift ;;
    --write-out) shift ;;
    --data) data="$2"; shift ;;
    --header|--connect-timeout|--max-time) shift ;;
    http*) url="$1" ;;
  esac
  shift || true
done
path="${url#*api/v2}"
printf '%s %s\n' "$method" "$path" >>"${MOCK_TRACE:?}"
printf '%s\n' "$data" >>"${MOCK_BODY:?}"
case "$method $path" in
  "GET /projects/prj_observability/branches/br_observability/roles")
    if [[ "${MOCK_ROLE_MODE:-}" == existing ]]; then
      body='{"roles":[{"name":"observabilitobservabilitobservabilitobservability_app"}]}'
    else
      body='{"roles":[]}'
    fi
    ;;
  "POST /projects/prj_observability/branches/br_observability/roles")
    body='{"role":{"name":"observabilitobservabilitobservabilitobservability_app","password":"provider-generated-password"},"operations":[]}'
    ;;
  "GET /projects/prj_observability/branches/br_observability/databases")
    if [[ "${MOCK_DATABASE_MODE:-}" == existing ]]; then
      body='{"databases":[{"name":"observabilitobservabilitobservabilitobservability_db"}]}'
    else
      body='{"databases":[]}'
    fi
    ;;
  "POST /projects/prj_observability/branches/br_observability/databases")
    body='{"database":{"name":"observabilitobservabilitobservabilitobservability_db","owner_name":"observabilitobservabilitobservabilitobservability_app"},"operations":[]}'
    ;;
  *) body='{}' ;;
esac
printf '%s' "$body" >"$output"
printf '200'
CURL
chmod 755 "$temp_dir/bin/curl"

export PATH="$temp_dir/bin:$PATH"
export PORTMASON_SHARE="$temp_dir/share" TEST_LOG="$temp_dir/log"
export MOCK_TRACE="$temp_dir/trace" MOCK_BODY="$temp_dir/body"
export DEPLOY_ENV=dev DB_API_KEY=test-api-key
export DB_PROJECT_ID=prj_observability DB_BRANCH_ID=br_observability
export OBSERVABILITY_DB_USER=observabilitobservabilitobservabilitobservability_app OBSERVABILITY_DB_PASSWORD=placeholder

. "$temp_dir/share/pm-helpers-neon"

export MOCK_ROLE_MODE=create
pm_observability_neon_ensure_application_role
[[ "$OBSERVABILITY_DB_PASSWORD" == provider-generated-password ]]
grep -Fq 'POST /projects/prj_observability/branches/br_observability/roles' "$temp_dir/trace"
export OBSERVABILITY_DB_NAME=observabilitobservabilitobservability_db
export MOCK_DATABASE_MODE=create
pm_observability_neon_ensure_application_database
grep -Fq 'POST /projects/prj_observability/branches/br_observability/databases' "$temp_dir/trace"
grep -Fqx '{"database":{"name":"observability_db","owner_name":"observability_app"}}' "$temp_dir/body"

export MOCK_DATABASE_MODE=existing
pm_observability_neon_ensure_application_database
[[ "$(grep -Fc 'POST /projects/prj_observability/branches/br_observability/databases' "$temp_dir/trace")" -eq 1 ]]
grep -Fq 'using existing Neon observability database' "$temp_dir/log"
grep -Fqx '{"role":{"name":"observabilitobservabilitobservability_app"}}' "$temp_dir/body"
! grep -Fq 'provider-generated-password' "$temp_dir/log"

export MOCK_ROLE_MODE=existing
OBSERVABILITY_DB_PASSWORD=existing-secret
pm_observability_neon_ensure_application_role
[[ "$OBSERVABILITY_DB_PASSWORD" == existing-secret ]]
[[ "$(grep -Fc 'POST /projects/prj_observability/branches/br_observability/roles' "$temp_dir/trace")" -eq 1 ]]
grep -Fq 'using existing Neon observability role' "$temp_dir/log"

printf 'PASS: Neon observability role lifecycle\n'
