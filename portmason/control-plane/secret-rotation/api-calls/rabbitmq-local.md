# Local RabbitMQ password rotation

Accepted secret:

- `INBOUND_EVENT_STORAGE_PASSWORD`

Service-side call:

```bash
docker compose exec -T queue rabbitmqctl change_password \
  "$INBOUND_EVENT_STORAGE_USER" \
  "$NEW_INBOUND_EVENT_STORAGE_PASSWORD"
```

Confirmation:

```bash
docker compose exec -T queue rabbitmqctl authenticate_user \
  "$INBOUND_EVENT_STORAGE_USER" \
  "$NEW_INBOUND_EVENT_STORAGE_PASSWORD"
```

Control-plane rule:

- Change RabbitMQ first.
- Confirm authentication.
- Then update the environment.

