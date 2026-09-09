#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
volumes_to_remove=""
volumes_to_preserve=""
set -- --minimal
# shellcheck disable=SC1090
source "$root/pm-container-nuke"

declare -A test_owners=(
    [orphan]=""
    [db_data]="db1"
    [archive_data]="archive1"
    [cache_data]="cache1"
    [unknown_data]="unknown1"
    [shared_data]="worker1 db2"
)
declare -A test_tiers=(
    [db1]="persistence"
    [archive1]="internal"
    [cache1]="internal"
    [unknown1]=""
    [worker1]="internal"
    [db2]="persistence"
)
declare -A test_lifecycles=(
    [db1]="persistent"
    [archive1]="archival"
    [cache1]="transient"
    [unknown1]=""
    [worker1]="transient"
    [db2]="persistent"
)

volume_owner_containers() {
    local volume_name="${1:?volume required}"
    tr ' ' '\n' <<<"${test_owners[$volume_name]-}" | sed '/^$/d'
}

container_label() {
    local container_id="${1:?container required}"
    local label_name="${2:?label required}"
    case "$label_name" in
        solutions.etal.service_tier) printf '%s' "${test_tiers[$container_id]-}" ;;
        solutions.etal.data_lifecycle) printf '%s' "${test_lifecycles[$container_id]-}" ;;
        *) return 1 ;;
    esac
}

container_display_name() {
    printf '%s' "${1:?container required}"
}

assert_decision() {
    local volume_name="${1:?volume required}"
    local expected="${2:?decision required}"
    local reason_fragment="${3:?reason required}"
    volume_removal_decision "$volume_name"
    [[ "$VOLUME_DECISION" == "$expected" ]]
    [[ "$VOLUME_REASON" == *"$reason_fragment"* ]]
}

assert_decision orphan preserve 'no owning container metadata'
assert_decision db_data preserve 'persistence tier'
assert_decision archive_data preserve 'data_lifecycle=archival'
assert_decision cache_data remove 'explicitly declares transient data'
assert_decision unknown_data preserve 'incomplete Portmason metadata'
assert_decision shared_data preserve 'persistence tier'

classify_candidate_volumes $'orphan\ndb_data\narchive_data\ncache_data\nunknown_data\nshared_data'
[[ "$volumes_to_remove" == cache_data ]]
grep -Fxq orphan <<<"$volumes_to_preserve"
grep -Fxq db_data <<<"$volumes_to_preserve"
grep -Fxq shared_data <<<"$volumes_to_preserve"

printf 'PASS: container nuke removes only explicitly transient volumes.\n'
