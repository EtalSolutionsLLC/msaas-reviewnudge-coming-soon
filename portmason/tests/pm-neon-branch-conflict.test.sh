#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
mkdir -p "$temp_dir/bin" "$temp_dir/state"
trace="$temp_dir/trace.log"
log_file="$temp_dir/test.log"

cat > "$temp_dir/pm-helpers" <<'HELPERS'
log() { printf '%s\n' "$*" >>"$TEST_LOG"; }
die() { log ERROR "$*"; return "${2:-1}"; }
env_init_set() { printf -v "$1" '%s' "${2-}"; export "$1"; }
pm_secret_resolve_value() { printf -v "$1" '%s' "${3-}"; }
HELPERS

cat > "$temp_dir/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
method=GET output="" url="" status=200
while (($#)); do
  case "$1" in
    --request) method="$2"; shift ;;
    --output) output="$2"; shift ;;
    --write-out) shift ;;
    --data|--header|--connect-timeout|--max-time) shift ;;
    http*) url="$1" ;;
  esac
  shift || true
done
path="${url#*api/v2}"
printf '%s %s\n' "$method" "$path" >>"${MOCK_TRACE:?}"
case "$method $path" in
  "GET /projects?limit=100")
    marker="${MOCK_STATE:?}/project-listed"
    if [[ "${MOCK_CONFLICT_KIND:-}" == project && -e "$marker" ]]; then
      body='{"projects":[{"id":"prj_conflict_062","name":"customer"}]}'
    elif [[ "${MOCK_CONFLICT_KIND:-}" == project ]]; then
      : >"$marker"; body='{"projects":[]}'
    else
      body='{"projects":[]}'
    fi
    ;;
  "POST /projects")
    body='{"message":"project already exists"}'; status=409
    ;;
  "GET /projects/prj_062/branches")
    marker="${MOCK_STATE:?}/branch-listed"
    if [[ "${MOCK_CONFLICT_KIND:-}" == branch && -e "$marker" ]]; then
      body='{"branches":[{"id":"br_prod_062","name":"production"}]}'
    elif [[ "${MOCK_CONFLICT_KIND:-}" == branch ]]; then
      : >"$marker"; body='{"branches":[]}'
    else
      body='{"branches":[]}'
    fi
    ;;
  "POST /projects/prj_062/branches")
    body='{"message":"branch already exists"}'; status=409
    ;;
  "GET /projects/prj_062/endpoints")
    marker="${MOCK_STATE:?}/endpoint-listed"
    if [[ "${MOCK_CONFLICT_KIND:-}" == endpoint && -e "$marker" ]]; then
      body='{"endpoints":[{"id":"ep_prod_062","branch_id":"br_prod_062","type":"read_write","disabled":false}]}'
    elif [[ "${MOCK_CONFLICT_KIND:-}" == endpoint ]]; then
      : >"$marker"; body='{"endpoints":[]}'
    else
      body='{"endpoints":[]}'
    fi
    ;;
  "POST /projects/prj_062/endpoints")
    body='{"message":"read_write endpoint already exists"}'; status=409
    ;;
  *) body='{}' ;;
esac
printf '%s' "$body" >"$output"
printf '%s' "$status"
CURL
chmod 755 "$temp_dir/bin/curl"

export PATH="$temp_dir/bin:$PATH"
export PORTMASON_SHARE="$temp_dir" TEST_LOG="$log_file"
export MOCK_TRACE="$trace" MOCK_STATE="$temp_dir/state"
export DEPLOY_ENV=dev DB_API_KEY=test-api-key
export DB_PROJECT_ID=prj_062 DB_BRANCH_NAME=production

. "$source_dir/pm-helpers-neon"
sed '$d' "$source_dir/pm-provision-db-neon" > "$temp_dir/pm-provision-db-neon"
. "$temp_dir/pm-provision-db-neon"

export MOCK_CONFLICT_KIND=branch
neon_ensure_branch
[[ "$DB_BRANCH_ID" == br_prod_062 ]]
grep -Fq "using existing branch after create conflict" "$log_file"

export MOCK_CONFLICT_KIND=endpoint
unset NEON_ENDPOINT_ID
neon_ensure_endpoint
[[ "$NEON_ENDPOINT_ID" == ep_prod_062 ]]
grep -Fq "using existing endpoint after create conflict" "$log_file"

export MOCK_CONFLICT_KIND=project
unset DB_PROJECT_ID
export DB_PROJECT_NAME=customer
neon_ensure_project
[[ "$DB_PROJECT_ID" == prj_conflict_062 ]]
grep -Fq "using existing project after create conflict" "$log_file"

! grep -Fq "API returned HTTP 409" "$log_file"
printf "Portmason Neon create-conflict reuse tests passed.\n"
