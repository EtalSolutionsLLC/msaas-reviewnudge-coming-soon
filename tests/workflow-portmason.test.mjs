import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const workflow = readFileSync('.github/workflows/gen-site-html.yml', 'utf8');

test('GitHub Pages generation enters the selected deployment root and delegates to pm-setup', () => {
  assert.match(workflow, /cd "\$\{DEPLOY_ROOT\}"/);
  assert.match(workflow, /PM_DEFER_SITE_BUILD_FINALIZE=true/);
  assert.match(workflow, /\bpm-setup\b/);
  assert.doesNotMatch(workflow, /\bpm-process-site-partials\b/);
});

test('workflow pins and verifies the shared Portmason tooling revision', () => {
  assert.match(workflow, /\.portmason-tooling-ref/);
  assert.match(workflow, /\^\[0-9a-f\]\{40\}\$/);
  assert.match(workflow, /repository:\s*domer6811\/ops-and-sops/);
  assert.match(workflow, /ops\/portmason/);
  assert.match(workflow, /actual_tooling_ref="\$\(git -C "\$\{GITHUB_WORKSPACE\}\/ops-and-sops" rev-parse HEAD\)"/);
  assert.match(workflow, /pm-version validate/);
});

test('workflow rejects a project-local pm-version implementation', () => {
  assert.match(workflow, /if \[\[ -e bin\/pm-version \]\]/);
  assert.match(workflow, /Project-local bin\/pm-version must not exist/);
  assert.match(workflow, /expected_pm_version="\$\{GITHUB_WORKSPACE\}\/ops-and-sops\/ops\/portmason\/pm-version"/);
});
