# Portmason credential runner

This is the first runnable slice of Portmason credential-control.

It is intentionally narrow:

- vendor-neutral command surface
- Docker Compose runnable
- direct or proxy/VPN egress through standard proxy environment variables
- local JSONL audit
- first adapter: Cloudflare Turnstile secret rotation
- first target: environment file materialization

The runner does not replace `pm-setup`. It prepares credential state; `pm-setup`
still applies the environment contract.

## Host usage

```bash
pm-control-plane secrets inventory --env-file /home/davidomer/code/msaas-reviewnudge/.env
pm-control-plane secrets egress
pm-control-plane secrets rotate --secret TURNSTILE_SECRET_KEY --env-file /home/davidomer/code/msaas-reviewnudge/.env --plan
pm-control-plane secrets rotate --secret TURNSTILE_SECRET_KEY --env-file /home/davidomer/code/msaas-reviewnudge/.env --apply
```

## Docker usage

Copy `.env.operator.example` to `.env.operator` and place only operator-control
credentials there.

```bash
cd /home/davidomer/code/ops-and-sops/ops/portmason/control-plane/credential-runner
docker compose run --rm pm-credential-control egress
docker compose run --rm pm-credential-control inventory --env-file /workspace/.env
docker compose run --rm pm-credential-control rotate --secret TURNSTILE_SECRET_KEY --env-file /workspace/.env --plan
docker compose run --rm pm-credential-control rotate --secret TURNSTILE_SECRET_KEY --env-file /workspace/.env --apply
```

## Egress

For zero-cost direct mode, the vendor APIs see the host/container public IP.

For controlled egress, set one of:

```text
HTTPS_PROXY
HTTP_PROXY
ALL_PROXY
```

Those are deliberately generic. The control plane should not care whether the
stable path is a forward proxy, VPN exit node, or another boring network route.

## Safety

- The runner prints fingerprints, never secret values.
- Apply mode backs up the environment file first.
- Old provider credentials are not revoked automatically in this first slice.
- Turnstile rotation uses Cloudflare's overlap window; run `pm-setup` and
  browser-test signup after rotation.
