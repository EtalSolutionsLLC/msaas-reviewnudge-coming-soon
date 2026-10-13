# Secret rotation adapter contract

The control plane should treat secret rotation as a state machine.

```text
planned
  -> service_changed
  -> service_confirmed
  -> env_materialized
  -> workload_reloaded
  -> smoke_tested
  -> old_secret_revoked
```

## Required adapter behavior

### `pm_secret_rotate_prepare`

Inputs:

- secret name
- current environment
- provider/platform code
- desired rotation mode

Outputs:

- rotation id
- generated candidate value, if Portmason-owned
- provider request plan, if service-owned
- list of affected workloads

No external mutation.

### `pm_secret_rotate_apply_service`

Performs the service-side change.

Examples:

- `ALTER USER ... PASSWORD ...` for local Postgres
- Neon reset-password API for Neon
- RabbitMQ `change_password`
- Resend API key creation
- Cloudflare Turnstile rotate-secret call

Must not update `.env`.

### `pm_secret_rotate_confirm_service`

Verifies the new credential against the owning service.

Examples:

- connect to Postgres with the new password
- authenticate RabbitMQ user
- call Resend list API with the new key
- verify Turnstile token path in an app smoke test

Must fail closed.

### `pm_secret_rotate_materialize_env`

Writes the new credential into the target environment only after confirmation.

Rules:

- backup first
- do not print secret values
- print key names and fingerprints only
- preserve comments and unrelated values where possible

### `pm_secret_rotate_revoke_old`

Revokes/deletes the previous provider credential after deployment and smoke
tests.

Default should be manual/explicit. No automatic old-secret revocation in the
first production-safe version.

