#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
case "$temp_dir" in
    /tmp/*) ;;
    *)
        printf 'Unsafe temporary directory: %s\n' "$temp_dir" >&2
        exit 1
        ;;
esac
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM

mkdir -p "$temp_dir/bin" "$temp_dir/project"
trace_file="$temp_dir/gcloud.trace"
state_file="$temp_dir/traffic.state"

cat >"$temp_dir/project/.env" <<'ENV'
DEPLOY_ENV=prd
DEPLOYMENT_ID=reviewnudge-prd-1778712786
RUNTIME_ADAPTER_CODE=node-gcp
ENV

cat >"$temp_dir/bin/gcloud" <<'GCLOUD'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$@" >>"${MOCK_TRACE:?}"
printf '\n' >>"${MOCK_TRACE:?}"

case "$1 $2 $3" in
    "run services list")
        cat <<'JSON'
[
  {
    "metadata": {
      "name": "reviewnudge-prd-web",
      "labels": {"cloud.googleapis.com/location": "us-central1"}
    }
  },
  {
    "metadata": {
      "name": "reviewnudge-prd-worker",
      "labels": {"cloud.googleapis.com/location": "us-central1"}
    }
  }
]
JSON
        ;;
    "run services describe")
        revision="reviewnudge-prd-web-00122-b2z"
        [[ -s "${MOCK_STATE:?}" ]] && revision="$(<"$MOCK_STATE")"
        printf '{"status":{"traffic":[{"revisionName":"%s","percent":100}]}}\n' "$revision"
        ;;
    "run revisions list")
        cat <<'JSON'
[
  {
    "metadata": {
      "name": "reviewnudge-prd-web-00122-b2z",
      "creationTimestamp": "2026-08-18T03:16:34.820031Z"
    },
    "status": {"conditions": [{"type": "Ready", "status": "True"}]}
  },
  {
    "metadata": {
      "name": "reviewnudge-prd-web-00121-cmm",
      "creationTimestamp": "2026-08-18T03:14:04.188589Z"
    },
    "status": {"conditions": [{"type": "Ready", "status": "True"}]}
  },
  {
    "metadata": {
      "name": "reviewnudge-prd-web-00120-wvt",
      "creationTimestamp": "2026-08-18T02:45:56.725556Z"
    },
    "status": {"conditions": [{"type": "Ready", "status": "True"}]}
  },
  {
    "metadata": {
      "name": "reviewnudge-prd-web-00119-fcz",
      "creationTimestamp": "2026-08-18T02:43:04.457432Z"
    },
    "status": {"conditions": [{"type": "Ready", "status": "True"}]}
  },
  {
    "metadata": {
      "name": "reviewnudge-prd-web-00118-5cw",
      "creationTimestamp": "2026-08-18T00:37:18.825422Z"
    },
    "status": {"conditions": [{"type": "Ready", "status": "True"}]}
  }
]
JSON
        ;;
    "run services update-traffic")
        for argument in "$@"; do
            case "$argument" in
                --to-revisions=*)
                    revision="${argument#--to-revisions=}"
                    printf '%s\n' "${revision%=100}" >"${MOCK_STATE:?}"
                    ;;
            esac
        done
        printf 'Traffic updated.\n'
        ;;
    *)
        printf 'Unexpected mock gcloud command: %s\n' "$*" >&2
        exit 9
        ;;
esac
GCLOUD
chmod +x "$temp_dir/bin/gcloud"

export PATH="$temp_dir/bin:$PATH"
export MOCK_TRACE="$trace_file"
export MOCK_STATE="$state_file"

output="$(
    cd "$temp_dir/project"
    printf '1\n3\ny\n' | "$root/pm-rollback" 2>&1
)"

grep -Fq 'runtime_adapter_code=node-gcp' <<<"$output"
grep -Fq 'script=pm-rollback-gcp' <<<"$output"
grep -Fq '1) reviewnudge-prd-web (us-central1)' <<<"$output"
grep -Fq '2) reviewnudge-prd-worker (us-central1)' <<<"$output"
grep -Fq '1) reviewnudge-prd-web-00122-b2z' <<<"$output"
grep -Fq '[ACTIVE]' <<<"$output"
grep -Fq '3) reviewnudge-prd-web-00120-wvt' <<<"$output"
grep -Fq 'Cloud Run rollback verified' <<<"$output"

grep -Fq -- \
    'run services list --project reviewnudge-prd-1778712786 --platform managed --format json' \
    "$trace_file"
grep -Fq -- \
    'run services update-traffic reviewnudge-prd-web --project reviewnudge-prd-1778712786 --region us-central1 --platform managed --to-revisions=reviewnudge-prd-web-00120-wvt=100' \
    "$trace_file"
[[ "$(<"$state_file")" == "reviewnudge-prd-web-00120-wvt" ]]
[[ ! -e "$temp_dir/project/.env.generated" ]]

bash -n "$root/pm-rollback" "$root/pm-rollback-gcp"

printf 'PASS: environment-selected GCP Cloud Run rollback contract\n'
