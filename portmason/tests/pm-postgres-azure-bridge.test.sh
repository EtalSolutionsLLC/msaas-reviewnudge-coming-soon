#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PORTMASON_SHARE="$(cd -- "${TEST_DIR}/.." && pwd -P)"
export PORTMASON_SHARE

bridge="${PORTMASON_SHARE}/pm-db-bridge-postgres-azure"
bash -n "$bridge"

grep -Fq 'postgres.database.azure.com' "$bridge"
grep -Fq 'pm_db_postgres_build_url runtime_url' "$bridge"
grep -Fq 'pm_db_publish_generated_contract' "$bridge"
grep -Fq 'PGSSLMODE=require' "$bridge"
grep -Fq '"$POSTGRES_TOOL_IMAGE"' "$bridge"

printf 'PASS: PostgreSQL Azure bridge contract is present\n'
