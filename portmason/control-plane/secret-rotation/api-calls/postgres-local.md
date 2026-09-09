# Local Postgres password rotation

Accepted secret:

- `DB_PASSWORD`

Service-side call:

```bash
docker compose exec -T db sh -lc '
  psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    -v new_password="$1" \
    -c "ALTER USER \"$POSTGRES_USER\" WITH PASSWORD :'\'new_password\'';"
' sh "$NEW_DB_PASSWORD"
```

Confirmation:

```bash
docker compose exec -T db sh -lc '
  PGPASSWORD="$1" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    -c "select current_user;"
' sh "$NEW_DB_PASSWORD"
```

Control-plane rule:

- Change the DB first.
- Confirm connection with the new password.
- Then update the environment.

