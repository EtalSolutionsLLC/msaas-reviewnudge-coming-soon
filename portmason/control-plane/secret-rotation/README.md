# Portmason control-plane secret rotation

Secret rotation is a Portmason control-plane capability.

Applications declare the secrets they need. Portmason owns the rotation
machinery because the work crosses application, runtime, database, queue,
messaging, billing, DNS, and provider-control boundaries.

Core rule:

1. Rotate or create the credential in the owning service.
2. Confirm the new credential works.
3. Update the environment file or secret store.
4. Re-render generated runtime configuration.
5. Restart/redeploy affected workloads.
6. Smoke-test.
7. Revoke old provider credentials only after the new path is proven.

Never update `.env` first for a service-owned password. `.env` is the app's
instruction sheet, not the source of truth for the provider.

## Proposed command surface

```bash
pm-control-plane secrets inventory
pm-control-plane secrets rotate --plan
pm-control-plane secrets rotate --secret DB_PASSWORD --apply
pm-control-plane secrets rotate --all --apply
pm-control-plane secrets revoke-old --rotation-id <id>
```

`pm-setup` remains the deployment entrypoint. The control-plane command prepares
the credential state, then `pm-setup` consumes the resulting environment.

## Adapter contract

Every adapter follows the same provider-neutral function names:

```bash
pm_secret_rotate_prepare
pm_secret_rotate_apply_service
pm_secret_rotate_confirm_service
pm_secret_rotate_materialize_env
pm_secret_rotate_revoke_old
```

The adapter may do Stripe, Neon, RabbitMQ, Resend, Cloudflare, Slack, or local
Postgres work internally. The orchestrator should not need provider-specific
function names.

## Library

Exact service-side call cards live in:

```text
control-plane/secret-rotation/api-calls/
```

Those cards are source material for future executable adapters.

## Runnable first slice

The first executable credential-control runner lives in:

```text
control-plane/credential-runner/
```

It currently supports Cloudflare Turnstile secret rotation and env-file
materialization through the provider-neutral command surface:

```bash
pm-control-plane secrets inventory --env-file <path>
pm-control-plane secrets egress
pm-control-plane secrets rotate --secret TURNSTILE_SECRET_KEY --env-file <path> --plan
pm-control-plane secrets rotate --secret TURNSTILE_SECRET_KEY --env-file <path> --apply
```
