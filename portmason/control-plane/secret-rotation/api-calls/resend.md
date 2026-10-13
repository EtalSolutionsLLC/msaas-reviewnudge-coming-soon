# Resend API key rotation

Accepted secret:

- `EMAIL_API_KEY` or app-specific email API key mapped into runtime config

Create replacement:

```bash
curl -X POST "https://api.resend.com/api-keys" \
  -H "Authorization: Bearer ${RESEND_ADMIN_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Portmason rotated key",
    "permission": "sending_access"
  }'
```

List keys:

```bash
curl -X GET "https://api.resend.com/api-keys" \
  -H "Authorization: Bearer ${RESEND_ADMIN_API_KEY}"
```

Delete old key after smoke tests:

```bash
curl -X DELETE "https://api.resend.com/api-keys/${OLD_RESEND_API_KEY_ID}" \
  -H "Authorization: Bearer ${RESEND_ADMIN_API_KEY}"
```

Control-plane rule:

- Create new key.
- Capture `.token`.
- Confirm key by calling a low-risk API endpoint.
- Then update the environment.
- Delete old key only after deployment smoke tests.

Sources:

- https://resend.com/docs/api-reference/api-keys/create-api-key
- https://resend.com/docs/api-reference/api-keys/list-api-keys
- https://resend.com/docs/api-reference/api-keys/delete-api-key

