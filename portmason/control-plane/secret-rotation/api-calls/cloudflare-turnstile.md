# Cloudflare Turnstile secret rotation

Accepted secret:

- runtime Turnstile secret key

Official dashboard path:

```text
Cloudflare Dashboard > Turnstile > Widget > Settings > Rotate Secret Key
```

Cloudflare documents a two-hour overlap where both old and new secrets are
valid.

API call to retain for adapter implementation:

```bash
curl -X POST \
  "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/challenges/widgets/${TURNSTILE_SITE_KEY}/rotate_secret" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json"
```

Control-plane rule:

- Rotate in Cloudflare.
- Capture new secret.
- Update environment during the overlap.
- Smoke-test human verification before the overlap ends.

Sources:

- https://developers.cloudflare.com/turnstile/troubleshooting/rotate-secret-key/
- https://developers.cloudflare.com/turnstile/get-started/widget-management/api/

