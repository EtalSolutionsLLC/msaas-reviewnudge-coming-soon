# Neon role/password rotation

Accepted secrets:

- `DB_API_KEY` for Neon control-plane access
- `DB_PASSWORD` for runtime database access

Verified endpoint:

```text
POST /projects/{project_id}/branches/{branch_id}/roles/{role_name}/reset_password
```

Service-side call:

```bash
curl -X POST \
  "https://console.neon.tech/api/v2/projects/${NEON_PROJECT_ID}/branches/${NEON_BRANCH_ID}/roles/${DB_USER}/reset_password" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${DB_API_KEY}"
```

Expected result includes:

```json
{
  "role": {
    "password": "new password appears once"
  }
}
```

Alternative chosen-password path:

```sql
ALTER USER reviewnudge_app WITH PASSWORD 'new-password';
```

Control-plane rule:

- Capture `.role.password`.
- Confirm a database connection with it.
- Then update the environment.

Sources:

- https://neon.com/docs/manage/roles
- https://api-docs.neon.tech/reference/getprojectbranchrolepassword

