# PM Configuration Manager

Version: Build 087  
Status: Initial production contract

## Purpose

PM Configuration Manager is Portmason's authoritative configuration registry,
validation, scoping, translation, and injection capability.

It separates four concerns:

1. A source key names the canonical operator or Portmason input.
2. A type classifies the value as a runtime variable, runtime secret, or
   control-plane secret.
3. A configuration scope identifies which services may receive the value.
4. A target key names the provider-native or application-native environment
   variable that is delivered to the destination.

The manager never treats provider-native output names as competing sources of
truth.

## Stable module model

Portmason configuration follows the normal entity, bridge, and phase model:

```text
pm-helpers-<entity>          source-safe reusable entity behavior
pm-bridge-<left>-<right>     pair-specific translation when required
pm-config-<entity>           configuration-phase registration and application
pm-provision-<entity>        provisioning phase
pm-setup-<entity>            setup phase
pm-deploy-<entity>           deployment phase
```

Helpers define capabilities. Bridges translate a concrete pair. Phase modules
perform lifecycle work. The orchestrator discovers and invokes them; it does
not absorb entity-specific behavior.

## Authoritative selectors

PM Configuration Manager discovers entities from the current shared context at
the phase in which it runs.

```text
RUNTIME_ADAPTER_CODE=<runtime>-<adapter>
DB_PROVIDER_PLATFORM_CODE=<provider>-<platform>
PM_<DOMAIN>_PROVIDER=<entity>
```

Examples:

```dotenv
RUNTIME_ADAPTER_CODE=node-gcp
DB_PROVIDER_PLATFORM_CODE=postgres-neon
PM_SUPPORT_CHANNEL_PROVIDER=slack
PM_EDGE_TUNNEL_PROVIDER=cloudflared
PM_ACME_DNS_PROVIDER=godaddy
```

The manager loads the corresponding `pm-config-*` modules lazily. Project-local
modules override shared modules when the canonical resolver permits it.

## Registry contract

Entity modules register values through:

```bash
pm_config_register KEY TYPE SCOPES TARGET REQUIRED [OWNER]
```

Fields:

```text
KEY       Canonical source key.
TYPE      var, secret, or control-plane.
SCOPES    Comma-separated runtime configuration scopes. Control-plane records
          must have no runtime scopes.
TARGET    Native key delivered to the destination.
REQUIRED  required or optional.
OWNER     Entity that owns the meaning of the record; normally inferred from
          the active pm-config-* module.
```

Example:

```bash
pm_config_register \
    PM_EDGE_TUNNEL_TOKEN \
    secret \
    'pm-edge-tunnel,cloudflared' \
    TUNNEL_TOKEN \
    required
```

The operator supplies `PM_EDGE_TUNNEL_TOKEN`. The cloudflared service receives
`TUNNEL_TOKEN`. Only a service requesting the matching scope may receive it.

## Service contract

Compose services retain the broad EPC classification and separately declare
configuration scopes:

```yaml
labels:
  solutions.etal.service: worker
  solutions.etal.config_scopes: application,database,pm-support-channel
```

`solutions.etal.service` answers what the service is.  
`solutions.etal.config_scopes` answers which configuration contracts it may
consume.

When `solutions.etal.config_scopes` is absent, the manager temporarily falls
back to the service role and Compose service name for compatibility. New and
updated projects should declare scopes explicitly.

## PM namespace

Portmason-owned operator inputs use `PM_`:

```dotenv
PM_EDGE_TUNNEL_PROVIDER=cloudflared
PM_EDGE_TUNNEL_TOKEN=
PM_SUPPORT_CHANNEL_PROVIDER=slack
PM_ACME_DNS_PROVIDER=godaddy
```

Portmason commands and modules use `pm-`.

Unprefixed canonical values remain valid when they describe the portable
application/runtime contract itself, including:

```text
STACK
PROJECT_ID
DEPLOYMENT_ID
APP_HOST
APP_URL
DB_PROVIDER_CODE
DB_PLATFORM_CODE
DB_HOST
DB_PORT
DB_NAME
DB_USER
DB_PASSWORD
DATABASE_URL
```

## Project-local registrations

A project may add configuration without editing the shared Portmason
distribution by creating a source-safe file at:

```text
pm-config-project
```

It must define:

```bash
pm_config_project() {
    pm_config_register \
        EXAMPLE_API_TOKEN \
        secret \
        'example-worker' \
        EXAMPLE_API_TOKEN \
        required
}
```

The project module may register project-specific contracts. It must not perform
provisioning, deployment, or other mutation when sourced.

## Adapter behavior

### Local

`pm-config-local` writes one mode-0600 file per service under:

```text
.portmason/config/<service>.env
```

It also writes a non-secret manifest:

```text
.portmason/config/manifest.tsv
```

Projects must ignore `.portmason/` in version control. Compose may consume the
service file with `env_file`, while the registry remains the source of the
service boundary.

### GCP

The GCP integration delegates to the existing Cloud Run and Secret Manager
helpers:

- non-secrets become service-specific Cloud Run environment values;
- runtime secrets become service-specific Secret Manager references;
- IAM access is granted only to the service account that receives the secret;
- control-plane credentials are never injected into application services.

The GCP deploy module retains compatibility with the prior role-based helper
entrypoints for one transition cycle.

### GitHub

The GitHub adapter separates public and private configuration:

- only registered non-secret values are written to the GitHub Pages browser
  configuration artifact;
- GitHub Actions variables are synchronized with `gh variable set`;
- GitHub Actions secrets are synchronized through stdin with `gh secret set`;
- secret values are never written into the browser artifact or command-line
  arguments.

`PM_GITHUB_REPOSITORY` may specify `owner/repository`. Otherwise the helper asks
`gh` to resolve the active repository.

`PM_GITHUB_SYNC_ACTIONS_CONFIG` controls synchronization. The default is false
in development and true outside development.

### Azure and AWS

Build 087 defines the manager contract but does not invent Azure or AWS entity
behavior that is not present in the current Portmason distribution. Selecting
an unsupported adapter fails on the missing required `pm-config-<adapter>`
module. Support is added by supplying the corresponding source-safe helper and
phase module without changing the manager or callers.

## Compatibility

Build 087 replaces the static Build 084 secret registry with the unified
configuration registry. The following compatibility surfaces remain available:

```text
pm-secret-registry
pm_service_secret_keys
pm_service_secret_kv_nul
pm_service_nonsecret_kv_nul
PM_ADDITIONAL_SECRET_KEYS
```

They delegate to PM Configuration Manager and exist for transition, not as
independent authorities.

## Commands

From a project root:

```bash
pm-config-manager plan
pm-config-manager validate
pm-config-manager apply
```

`plan` prints metadata only and never prints values.  
`validate` discovers the active contract and checks required values.  
`apply` validates, runs bridge configuration hooks, and delegates injection to
the active adapter.

`pm-setup` runs the configuration phase after runtime setup modules and before
database/application deployment.

## Extension checklist

To add an entity:

1. Add `pm-helpers-<entity>` for reusable, source-safe behavior.
2. Add `pm-config-<entity>` with `pm_config_<entity>()` registrations.
3. Add `pm_config_apply_<entity>()` only when the entity performs configuration
   phase work.
4. Add a bridge only when a useful pair requires pair-specific translation.
5. Keep provisioning, setup, configuration, and deployment behavior in their
   corresponding phase modules.
6. Add tests proving scope isolation, secret non-disclosure, required-value
   validation, and backward compatibility where applicable.
