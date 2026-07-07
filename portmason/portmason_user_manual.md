# Portmason User Manual

Audience: junior developers  
Purpose: explain the Portmason commands in this package and when to use them.

---

## 1. What Portmason does

Portmason is a project setup and deployment helper.

It reads project environment files such as:

```text
.env
qas.env
prd.env
```

Then it decides what to run based on values like:

```env
APP_SLUG=david
CM_ENV=dev
STACK=david-dev
RUNTIME_ADAPTER_CODE=static-github
```

The most important idea is:

```text
env file -> pm-setup -> provision/deploy/configure scripts
```

Do not hard-code environment behavior into the app. Put environment-specific behavior in the env file.

---

## 2. Core concepts

### Environment file

An environment file stores configuration for one environment.

Common examples:

```text
.env      # local development
qas.env   # QA environment
prd.env   # production environment
```

### Runtime adapter

`RUNTIME_ADAPTER_CODE` tells Portmason what kind of runtime and hosting target to use.

Examples from this package:

```text
wp-local
wp-gcp
static-github
bash-gcp
```

The adapter can be different per environment. For example:

```text
.env      -> wp-local
qas.env   -> wp-gcp
prd.env   -> wp-gcp
```

or:

```text
.env      -> static-github
prd.env   -> static-github
```

### STACK

`STACK` is the environment-specific name for the running project.

Example:

```env
APP_SLUG=david
CM_ENV=dev
STACK=david-dev
```

Use `STACK` to avoid name collisions between projects and environments.

### Static partials and page tokens

Some static sites use shared HTML partials so repeated page sections can be maintained in one place.

Common examples:

```text
partials/home-header.html
partials/case-header.html
partials/footer.html
```

A static page marks the area Portmason may refresh with managed region comments:

```html
<!-- PM:FOOTER -->
<!-- /PM:FOOTER -->
```

When `pm-deploy-static` runs, it replaces the content inside the managed region with the matching partial content.

Some partials can also use page-level substitution tokens. For example, a case-study header partial may contain:

```html
<small>{{CASE_SUBTITLE}}</small>
```

The page can provide that value using normal HTML custom data attributes:

```html
<body data-case-subtitle="Integration Case Study">
```

Naming rule:

```text
HTML page metadata: data-case-subtitle
Template token:      {{CASE_SUBTITLE}}
```

Keep HTML attributes in `data-kebab-case`. Keep Portmason/template tokens in `UPPER_SNAKE_CASE`.

---

## 3. Most common commands

### `pm-setup`

Main command. Use this first.

```bash
pm-setup
```

What it does:

1. Loads the current env file.
2. Determines the runtime and adapter.
3. Runs adapter provisioning if available.
4. Runs adapter/runtime setup if available.
5. Runs the project `setup` script if one exists.
6. Otherwise runs deploy logic.

Typical use:

```bash
cd ~/code/my-project
pm-setup
```

For most projects, this is the only command you should need at first.

---

### `pm-clone-project`

Copies the current project to a new folder and gives the clone a new `.project_timestamp`.

```bash
pm-clone-project ../new-project-folder
```

Use this when starting a new project from an existing Portmason-compatible project.

What it does:

- copies files from the current folder
- excludes old identity timestamp files
- writes a new `.project_timestamp`
- primes a default `.env.example` if no env files exist

---

### `pm-util-render-env`

Renders env-variable placeholders in files.

Basic use:

```bash
pm-util-render-env --dotenv .env --out .env.generated
```

JSON output:

```bash
pm-util-render-env --json .env --out config.generated.json
```

Use this when static/browser-safe config must be generated from an env file.

Important: browser-safe config should not include secrets.

---

### `pm-capture-state`

Captures project state for debugging or handoff.

```bash
pm-capture-state
```

Use this before asking for help or before making risky changes.

It is designed to keep going even if some checks fail.

---

## 4. Local development commands

### `pm-deploy-local`

Starts the current Docker Compose stack.

```bash
pm-deploy-local
```

What it does:

- uses `docker-compose.yml`
- also uses `docker-compose.override.yml` if present
- runs `docker compose up -d`

Usually you do not call this directly. `pm-setup` calls the right deploy command for you.

---

### `pm-provision-local`

Prepares local development support, especially HTTPS certificates when needed.

```bash
pm-provision-local
```

What it can do:

- prepare local TLS certificates
- use `mkcert` for `localtest.me`
- write Traefik certificate config

Usually run through:

```bash
pm-setup
```

---

### `pm-refresh-traefik`

Restarts the shared Traefik project and the current Docker Compose project.

```bash
pm-refresh-traefik
```

Use this after changing local routing, certificates, or Traefik labels.

---

### `pm-enter-container`

Opens a shell inside a project container.

```bash
pm-enter-container
```

Use this when you need to inspect files or run commands inside the container.

---

### `pm-container-logs`

Shows container logs for the current project.

```bash
pm-container-logs
```

Use this when a local container starts but the site does not work.

---

### `pm-container-nuke`

Removes Docker artifacts for the current stack.

```bash
pm-container-nuke
```

Use this when the local Docker state is broken and you need a clean rebuild.

Be careful. This is destructive.

Dangerous mode:

```bash
pm-container-nuke --all
```

Only use `--all` if you truly mean to remove Docker artifacts beyond the current stack.

---

### `pm-container-nuke-wp`

WordPress-specific hook used by `pm-container-nuke`.

You normally do not run this directly.

---

### `pm-ensure-external-networks`

Ensures external Docker networks referenced by a Compose file exist.

```bash
pm-ensure-external-networks
```

Optional compose file:

```bash
pm-ensure-external-networks docker-compose.yml
```

Use this when Docker Compose complains that an external network does not exist.

---

## 5. GitHub/static site commands

### `pm-deploy-static`

Renders static-site partials into managed page regions.

```bash
pm-deploy-static
```

Use this for static sites that keep repeated page sections in `partials/`.

Typical source partials:

```text
partials/home-header.html
partials/case-header.html
partials/footer.html
```

Typical managed regions in HTML pages:

```html
<!-- PM:HOME-HEADER -->
<!-- /PM:HOME-HEADER -->

<!-- PM:CASE-HEADER -->
<!-- /PM:CASE-HEADER -->

<!-- PM:FOOTER -->
<!-- /PM:FOOTER -->
```

What it does:

1. Reads known partial files from `partials/`.
2. Finds matching `<!-- PM:... -->` regions in static HTML pages.
3. Replaces only the content inside those managed regions.
4. Preserves the opening and closing markers.
5. Applies supported page-level token substitutions.

#### Page-specific partial values

A shared partial can include tokens that are different per page.

Example partial:

```html
<small>{{CASE_SUBTITLE}}</small>
```

Example page metadata:

```html
<body data-case-subtitle="Data / API Case Study">
```

When rendered, the final page becomes:

```html
<small>Data / API Case Study</small>
```

For case-study pages, `CASE_SUBTITLE` is resolved in this order:

1. The page's `<body data-case-subtitle="...">` value.
2. A matching value from `content/case-studies.json`, if the project supports it.
3. The fallback value `Architecture Case Study`.

#### Safe editing rules

Do edit:

```text
partials/*.html
<body data-case-subtitle="...">
content/case-studies.json
```

Do not manually edit rendered content inside managed regions unless you are also updating the source partial. Your changes will be overwritten the next time `pm-deploy-static` runs.

Usually run through:

```bash
pm-setup
```

You may run it directly when you only changed partials or page-level metadata.

---

### `pm-provision-github`

GitHub Pages provisioning is a no-op in this package.

```bash
pm-provision-github
```

Why: GitHub Pages is normally configured in GitHub repository settings or GitHub Actions.

---

### `pm-deploy-github`

Prepares a static GitHub Pages artifact locally.

```bash
pm-deploy-github
```

What it does:

- prepares the static site output directory
- renders static partials when the project provides `pm-deploy-static`
- generates browser-safe config
- logs the artifact directory

Usually run through:

```bash
pm-setup
```

---

### `pm-bridge-static-github`

Bridge file for `static-github` projects.

It intentionally does not provide a runtime shell command because GitHub Pages serves static files only.

You normally do not run this directly.

---

## 6. WordPress commands

### `pm-provision-wp`

Installs/configures WordPress core behavior for a WordPress runtime.

```bash
pm-provision-wp
```

Usually run through:

```bash
pm-setup
```

---

### `pm-configure-site-wp`

Runs WordPress site configuration.

```bash
pm-configure-site-wp
```

Use this after WordPress is running and you need to apply site settings/content.

---

### `pm-configure-site-boilerplate`

Shared boilerplate used by project-level configure scripts.

You normally do not run this directly.

---

### `pm-bridge-wp-local`

Provides the `rt` helper for local WordPress projects.

It runs WP-CLI through Docker Compose.

Example behavior:

```bash
rt option get siteurl
```

You normally use this indirectly from project scripts.

---

### `pm-bridge-wp-gcp`

Provides the `rt` helper for WordPress on GCP Cloud Run.

It resolves the Cloud Run URL and runs WP-CLI against the remote site.

You normally use this indirectly from project scripts.

---

### `pm-container-nuke-wp`

WordPress cleanup safety hook used during container nuking.

You normally do not run this directly.

---

## 7. GCP commands

### `pm-provision-gcp`

Prepares GCP resources for a project.

```bash
pm-provision-gcp
```

What it may do:

- select or create the GCP project
- enable required APIs
- create Artifact Registry repos
- create storage buckets
- configure IAM
- prepare secret access

Usually run through:

```bash
pm-setup
```

---

### `pm-deploy-gcp`

Builds/tags/pushes container images and deploys Cloud Run services or jobs.

```bash
pm-deploy-gcp
```

Usually run through:

```bash
pm-setup
```

---

### `pm-update-gcp`

Builds a new image and updates an existing Cloud Run job.

```bash
pm-update-gcp
```

Use this for job-style deployments after the project is already provisioned.

---

### `pm-get-logs-gcp`

Fetches GCP logs in loud/debug mode.

```bash
pm-get-logs-gcp
```

Use this when a Cloud Run service or job is failing.

---

### `pm-ensure-sqlinstance-gcp`

Ensures a GCP SQL instance exists.

```bash
pm-ensure-sqlinstance-gcp
```

This is one of the few scripts intended to be usable independently.

---

### `pm-emulate-cloudrun`

Builds and runs the current project locally in a Cloud Run-like Docker environment.

```bash
pm-emulate-cloudrun --image-tag my-test --port 8080 --env-file .env
```

Useful for testing Cloud Run behavior before deploying.

---

### `pm-emulate-runtime`

Higher-level runtime emulator.

```bash
pm-emulate-runtime
```

It prepares runtime artifacts and then delegates to Cloud Run emulation.

---

### `pm-bridge-bash-gcp`

Bridge placeholder for bash-on-GCP style projects.

You normally do not run this directly.

---

## 8. Python/CLI commands

### `pm-setup-cli`

Sets up a Python CLI-style runtime.

```bash
pm-setup-cli
```

Run the configured CLI:

```bash
pm-setup-cli run
```

Requires one of these env values:

```env
CLI_ENTRYPOINT_MODULE=my_package.cli
```

or:

```env
CLI_ENTRYPOINT_FILE=scripts/main.py
```

---

### `pm-provision-venv`

Creates/prepares a Python virtual environment.

```bash
pm-provision-venv
```

Usually used by CLI/Python workflows.

---

### `pm-helpers-venv`

Helper library for Python virtual environment workflows.

You do not run this directly.

---

## 9. .NET command

### `pm-create-api-dotnet`

Creates a starter .NET Web API solution with tests.

```bash
pm-create-api-dotnet MyProject
```

What it creates:

```text
MyProject/
  MyProject.sln
  src/MyProject.Api/
  tests/MyProject.Tests/
```

It also adds common Entity Framework packages and runs restore/build.

---

## 10. Database commands

### `pm-dbmigrate`

Dispatches to a runtime/adapter-specific database migration script.

```bash
pm-dbmigrate
```

Example dispatch pattern:

```text
pm-dbmigrate-dotnet-local
```

If no matching migration script exists, it does nothing.

---

### `pm-dbmigrate-dotnet-local`

Local .NET database migration command.

```bash
pm-dbmigrate-dotnet-local
```

Use this only for .NET/local projects that are set up for migrations.

---

## 11. Utility commands

### `pm-get-compose-images`

Reads Docker Compose image references.

```bash
pm-get-compose-images
```

Useful for debugging deploy/build behavior.

---

### `pm-update-docker-env-file`

Updates Docker env-file references in a Compose file.

```bash
pm-update-docker-env-file
```

Optional compose file:

```bash
pm-update-docker-env-file docker-compose.yml
```

---

### `pm-tools-wrap-image`

Wraps or prepares container images for tool/runtime workflows.

```bash
pm-tools-wrap-image
```

This is advanced. Use it only when a project README or runbook tells you to.

---

### `pm-publish-mgt-scripts-artifact`

Publishes management scripts as an artifact.

```bash
pm-publish-mgt-scripts-artifact
```

Use only when releasing or packaging management scripts.

---

### `pm-util-list-fn-names`

Lists Bash function names in a script.

```bash
pm-util-list-fn-names pm-helpers
```

Useful when reviewing helper libraries.

---

## 12. Helper files you normally do not run

These files are libraries or bridge modules. They are sourced by other scripts.

```text
pm-helpers
pm-helpers-base
pm-helpers-gcp
pm-helpers-github
pm-helpers-live-tail
pm-helpers-local
pm-helpers-node
pm-helpers-py
pm-helpers-static
pm-helpers-venv
pm-helpers-wp
pm-bridge-*
pm-cm-env-mapping.json
```

Do not run helper files directly unless a maintainer tells you to.

---

## 13. Typical workflows

### Local WordPress project

```bash
cd ~/code/my-wp-project
pm-setup
```

If containers are broken:

```bash
pm-container-logs
pm-container-nuke
pm-setup
```

### Static GitHub Pages project

```bash
cd ~/code/my-static-site
pm-setup
```

This should prepare generated browser config, render static partials if present, and prepare the static artifact.

If you only changed files in `partials/` or page metadata such as `data-case-subtitle`, you can render the static partials directly:

```bash
pm-deploy-static
```

### GCP project

```bash
cd ~/code/my-cloud-project
pm-setup
```

If it fails, check logs/state:

```bash
pm-capture-state
pm-get-logs-gcp
```

### Python CLI project

```bash
cd ~/code/my-cli
pm-setup-cli
pm-setup-cli run
```

---

## 14. Common mistakes

### Running from the wrong folder

Most commands expect to run from the project root.

Good:

```bash
cd ~/code/my-project
pm-setup
```

Bad:

```bash
cd ~/code
pm-setup
```

### Editing generated files by hand

Avoid editing files like:

```text
.env.generated
config.generated.json
```

Edit the source env file instead, then regenerate.

### Editing managed partial regions by hand

Avoid editing the rendered content inside Portmason-managed regions:

```html
<!-- PM:FOOTER -->
  rendered footer content
<!-- /PM:FOOTER -->
```

Edit the source partial instead:

```text
partials/footer.html
```

Then rerun:

```bash
pm-deploy-static
```

Page-specific values should live on the page as metadata, not inside the shared partial.

Good:

```html
<body data-case-subtitle="Integration Case Study">
```

Bad:

```html
<small>Integration Case Study</small>
```

inside a shared `partials/case-header.html` file.

### Putting secrets into browser config

Never put secrets into static/browser config.

Bad:

```env
API_SECRET=super-secret
```

Good:

```env
PUBLIC_SITE_NAME=David Omer
PUBLIC_ANALYTICS_ID=GTM-XXXXXXX
```

### Using the wrong adapter

`RUNTIME_ADAPTER_CODE` can vary by environment.

Do not assume DEV, QAS, and PRD use the same adapter.

---

## 15. Quick command reference

| Command | Use |
|---|---|
| `pm-setup` | Main setup/deploy command |
| `pm-clone-project` | Clone a project and stamp a new identity |
| `pm-util-render-env` | Generate dotenv or JSON output from env files |
| `pm-capture-state` | Capture debug/handoff state |
| `pm-deploy-local` | Start local Docker Compose stack |
| `pm-provision-local` | Prepare local certs/routing support |
| `pm-refresh-traefik` | Restart Traefik and current stack |
| `pm-container-logs` | View local container logs |
| `pm-container-nuke` | Remove Docker artifacts for current stack |
| `pm-deploy-static` | Render static partials into managed HTML regions |
| `pm-deploy-github` | Prepare GitHub Pages static artifact |
| `pm-provision-github` | GitHub Pages provision no-op |
| `pm-provision-gcp` | Prepare GCP resources |
| `pm-deploy-gcp` | Deploy to Cloud Run/GCP |
| `pm-get-logs-gcp` | Fetch GCP logs |
| `pm-emulate-cloudrun` | Run local Cloud Run-style emulator |
| `pm-setup-cli` | Setup/run Python CLI runtime |
| `pm-create-api-dotnet` | Create .NET Web API starter |
| `pm-dbmigrate` | Run matching DB migration script |

---

## 16. Rule of thumb

Start with:

```bash
pm-setup
```

Only use lower-level commands when:

1. the project README tells you to,
2. you are debugging a specific failure, or
3. a maintainer asks you to run one.
