# Slack token/signing-secret rotation

Accepted secrets:

- `RUNTIME_API_KEY` or app-specific Slack bot token
- app-specific Slack signing secret

Status:

- Slack supports OAuth token rotation for apps using OAuth V2 token rotation.
- Direct rotation of a stored `xoxb-...` bot token is not a complete adapter
  until the app stores the refresh-token/install model.
- Signing secret rotation remains dashboard/app-management driven until a
  supported app-management API path is adopted.

OAuth refresh call for token-rotation-enabled apps:

```bash
curl -X POST "https://slack.com/api/oauth.v2.access" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=refresh_token" \
  --data-urlencode "client_id=${SLACK_CLIENT_ID}" \
  --data-urlencode "client_secret=${SLACK_CLIENT_SECRET}" \
  --data-urlencode "refresh_token=${SLACK_REFRESH_TOKEN}"
```

Control-plane rule:

- Do not claim full Slack rotation support until Portmason has a Slack install
  store and refresh-token model.

Source:

- https://docs.slack.dev/tools/bolt-python/concepts/token-rotation

