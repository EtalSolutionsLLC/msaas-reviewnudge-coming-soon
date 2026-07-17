import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const workflow = readFileSync('.github/workflows/setup-maintain-deploy-via-portmason.yml', 'utf8');

test('GitHub Pages generation enters the selected deployment root and delegates to pm-setup', () => {
  assert.match(workflow, /working-directory: \$\{\{ env\.DEPLOY_DIR \}\}/);
  assert.match(workflow, /\bpm-setup\b/);
  assert.doesNotMatch(workflow, /\bpm-process-site-partials\b/);
});

test('workflow pins and verifies the shared Portmason tooling revision', () => {
  assert.match(workflow, /\.portmason-tooling-ref/);
  assert.match(workflow, /\^\[0-9a-f\]\{40\}\$/);
  assert.match(workflow, /repository:\s*domer6811\/ops-and-sops/);
  assert.match(workflow, /ops\/portmason/);
  assert.match(workflow, /ref: \$\{\{ steps\.portmason-ref\.outputs\.sha \}\}/);
  assert.match(workflow, /PORTMASON_SHARE/);
});

test('workflow uses the pinned shared Portmason implementation', () => {
  assert.match(workflow, /portmason_share="\$\{GITHUB_WORKSPACE\}\/\$\{OPS_DIR\}\/ops\/portmason"/);
  assert.match(workflow, /"\$\{PORTMASON_SHARE\}\/pm-setup"/);
  assert.doesNotMatch(workflow, /bin\/pm-version/);
});
