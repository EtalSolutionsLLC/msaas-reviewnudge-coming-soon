import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildInfoRows,
  isBuildInfoShortcut,
  normalizeBuildIdentity
} from '../web/pm-build-info.js';

test('Ctrl or Command + Shift + P opens the Build Identity command palette', () => {
  assert.equal(isBuildInfoShortcut({ key: 'P', ctrlKey: true, shiftKey: true, altKey: false }), true);
  assert.equal(isBuildInfoShortcut({ key: 'p', metaKey: true, shiftKey: true, altKey: false }), true);
  assert.equal(isBuildInfoShortcut({ key: 'p', ctrlKey: true, shiftKey: false, altKey: false }), false);
  assert.equal(isBuildInfoShortcut({ key: 'p', ctrlKey: true, shiftKey: true, altKey: true }), false);
});

test('normalization exposes only the canonical allowlisted build fields', () => {
  const identity = normalizeBuildIdentity(
    {
      releaseVersion: '1.2.3',
      buildNumber: '094',
      buildId: '094',
      officialBuild: true,
      sourceCommit: '1234567890abcdef1234567890abcdef12345678',
      sourceDirty: false,
      builtAt: '2026-07-11T19:30:00Z',
      artifactSha256: 'abc123',
      builder: 'Et al Solutions LLC',
      secret: 'must-not-escape'
    },
    {
      environment: 'prd',
      deploymentId: 'prd-42',
      deployedAt: '2026-07-11T19:35:00Z',
      verification: 'verified'
    },
    { productName: 'Example', releaseVersion: '', buildNumber: '' }
  );

  assert.equal(identity.productName, 'Example');
  assert.equal(identity.releaseVersion, '1.2.3');
  assert.equal(identity.buildNumber, '094');
  assert.equal(identity.sourceCommit, '1234567890ab');
  assert.equal(identity.environment, 'prd');
  assert.equal(identity.verification, 'verified');
  assert.equal(Object.hasOwn(identity, 'secret'), false);
});

test('display rows are stable and omit arbitrary metadata', () => {
  const rows = buildInfoRows(normalizeBuildIdentity({}, {}, { productName: 'Example' }));
  assert.equal(rows[0][0], 'Product');
  assert.equal(rows[0][1], 'Example');
  assert.equal(rows.some(([label]) => label === 'Artifact SHA-256'), true);
  assert.equal(rows.some(([label]) => label === 'Secret'), false);
});
