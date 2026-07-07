# Portmason buildout notes

Generated: 2026-05-12

## Confirmed architecture

Portmason uses `RUNTIME_ADAPTER_CODE=<runtime>-<adapter>` to load runtime helpers, adapter helpers, optional runtime-adapter bridges, provisioning scripts, setup scripts, and deploy scripts without modifying project code.

Examples:

- `bash-gcp` -> runtime `bash`, adapter `gcp`
- `wp-local` -> runtime `wp`, adapter `local`
- `static-github` -> runtime `static`, adapter `github`

## Important semantics preserved

- `CM_ENV` must be defined.
- `CM_ENV=""` means production.
- `CM_ENV="prd"` means production.
- `CM_ENV="dev"` is development.
- `CM_ENV="sys"` is system/tooling.
- Non-dev/non-sys setup still uses the `cm/<env>` folder model. The code now checks `is_env_dir`, which confirms the parent folder is named `cm`.

## Secret-store behavior

- `get_secret` now defaults bare secret specs to GCP.
- `gcs:` is treated as an alias for `gcp:`.
- Adapter-native secret stores can still override by implementing `get_<provider>_secret` and `get_<provider>_secret_name_from_path`.
- `SECRET_PATHS` now supports both Bash-array style and newline/string style definitions.

## Fixes / additions

- Added `--json` support to `pm-util-render-env`.
- Added `${VAR:+alternate}` support to `pm-util-render-env`.
- Improved nested expansion handling such as `${IMAGE_TAG:-${CM_ENV}}`.
- JSON output excludes likely secrets and runtime noise by default.
- Fixed `ensure_stack` to derive `STACK="${APP_SLUG}${CM_ENV:+-${CM_ENV}}"`.
- Fixed `pm-setup` non-dev sync behavior while preserving the `cm/<env>` rule.
- Fixed `pm-deploy-local` override compose path test.
- Fixed `pm-deploy-gcp` job env flag variable typo.
- Fixed `pm-update-gcp` `PORTMASON_SHARE` typo / bootstrap line.
- Fixed `pm-helpers-py` syntax errors.
- Completed `pm-bridge-wp-gcp` enough to be syntactically valid and dispatch WP-CLI against the resolved Cloud Run URL.
- Added first-pass `static-github` adapter files:
  - `pm-helpers-static`
  - `pm-helpers-github`
  - `pm-provision-github`
  - `pm-deploy-github`
  - `pm-bridge-static-github`

## Validation run

- `python3 -m py_compile pm-util-render-env`
- `bash -n` across all Bash `pm-*` files
- Rendered actual `.env` to JSON and confirmed secret-like keys are excluded.
- Confirmed empty `CM_ENV` renders `STACK=myapp` with no trailing dash.
- Confirmed `CM_ENV=dev` renders `STACK=myapp-dev`.
