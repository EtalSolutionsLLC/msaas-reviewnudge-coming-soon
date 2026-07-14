/**
 * Portmason Build Identity browser capability.
 *
 * Provides a reusable, framework-free command palette and build-information
 * dialog backed by Portmason's build-info.json and deploy-info.json contracts.
 */

const DEFAULT_BUILD_INFO_URL = '/build-info.json';
const DEFAULT_DEPLOY_INFO_URL = '/deploy-info.json';

function cleanString(value, fallback = '') {
  const text = String(value ?? '').trim();
  return text || fallback;
}

function shortCommit(value) {
  const text = cleanString(value);
  if (!text || text === 'unavailable') return text;
  return text.length > 12 ? text.slice(0, 12) : text;
}

function formatBoolean(value) {
  if (value === true) return 'Yes';
  if (value === false) return 'No';
  return '';
}

function formatDate(value) {
  const text = cleanString(value);
  if (!text) return '';
  const date = new Date(text);
  return Number.isNaN(date.getTime()) ? text : date.toLocaleString();
}

function metaContent(documentRef, name) {
  return cleanString(documentRef?.querySelector?.(`meta[name="${name}"]`)?.content);
}

export function isBuildInfoShortcut(event) {
  if (!event || event.altKey) return false;
  const key = cleanString(event.key).toLowerCase();
  return key === 'p' && Boolean(event.shiftKey) && Boolean(event.ctrlKey || event.metaKey);
}

export function readBuildInfoMetadata(documentRef = globalThis.document) {
  return {
    productName: metaContent(documentRef, 'application-name') || cleanString(documentRef?.title, 'Portmason application'),
    releaseVersion: metaContent(documentRef, 'etal-site-release'),
    buildNumber: metaContent(documentRef, 'etal-site-build'),
    buildInfoUrl: metaContent(documentRef, 'etal-site-build-info') || DEFAULT_BUILD_INFO_URL,
    deployInfoUrl: metaContent(documentRef, 'etal-site-deploy-info') || DEFAULT_DEPLOY_INFO_URL
  };
}

export function normalizeBuildIdentity(build = {}, deploy = {}, metadata = {}) {
  return {
    productName: cleanString(metadata.productName, 'Portmason application'),
    releaseVersion: cleanString(build.releaseVersion || deploy.releaseVersion || metadata.releaseVersion, 'Unavailable'),
    buildNumber: cleanString(build.buildNumber || deploy.buildNumber || metadata.buildNumber, 'Unavailable'),
    buildId: cleanString(build.buildId || deploy.buildId, 'Unavailable'),
    environment: cleanString(deploy.environment, 'Not recorded'),
    officialBuild: formatBoolean(build.officialBuild),
    sourceCommit: shortCommit(build.sourceCommit || deploy.sourceCommit) || 'Unavailable',
    sourceDirty: formatBoolean(build.sourceDirty),
    builtAt: formatDate(build.builtAt) || 'Unavailable',
    deployedAt: formatDate(deploy.deployedAt) || 'Not recorded',
    deploymentId: cleanString(deploy.deploymentId, 'Not recorded'),
    artifactSha256: cleanString(build.artifactSha256 || deploy.artifactSha256, 'Not sealed'),
    verification: cleanString(deploy.verification, 'Not recorded'),
    builder: cleanString(build.builder, 'Et al Solutions LLC')
  };
}

export function buildInfoRows(identity) {
  return [
    ['Product', identity.productName],
    ['Release', identity.releaseVersion],
    ['Build', identity.buildNumber],
    ['Build ID', identity.buildId],
    ['Environment', identity.environment],
    ['Official build', identity.officialBuild || 'Not recorded'],
    ['Built at', identity.builtAt],
    ['Deployed at', identity.deployedAt],
    ['Source commit', identity.sourceCommit],
    ['Source dirty', identity.sourceDirty || 'Not recorded'],
    ['Deployment ID', identity.deploymentId],
    ['Artifact SHA-256', identity.artifactSha256],
    ['Verification', identity.verification],
    ['Builder', identity.builder]
  ];
}

async function fetchJsonOptional(url, fetchRef) {
  try {
    const response = await fetchRef(url, {
      headers: { Accept: 'application/json' },
      cache: 'no-store',
      credentials: 'same-origin'
    });
    if (!response.ok) return {};
    const payload = await response.json();
    return payload && typeof payload === 'object' && !Array.isArray(payload) ? payload : {};
  } catch {
    return {};
  }
}

export async function loadBuildIdentity(options = {}) {
  const documentRef = options.documentRef || globalThis.document;
  const fetchRef = options.fetchRef || globalThis.fetch?.bind(globalThis);
  const metadata = readBuildInfoMetadata(documentRef);
  if (!fetchRef) return normalizeBuildIdentity({}, {}, metadata);

  const [build, deploy] = await Promise.all([
    fetchJsonOptional(options.buildInfoUrl || metadata.buildInfoUrl, fetchRef),
    fetchJsonOptional(options.deployInfoUrl || metadata.deployInfoUrl, fetchRef)
  ]);
  return normalizeBuildIdentity(build, deploy, metadata);
}

function showDialog(dialog) {
  if (!dialog) return;
  if (typeof dialog.showModal === 'function') dialog.showModal();
  else dialog.setAttribute('open', '');
}

function closeDialog(dialog) {
  if (!dialog) return;
  if (typeof dialog.close === 'function') dialog.close();
  else dialog.removeAttribute('open');
}

function element(documentRef, tag, attributes = {}, text = '') {
  const node = documentRef.createElement(tag);
  for (const [key, value] of Object.entries(attributes)) {
    if (key === 'className') node.className = value;
    else if (key === 'dataset') Object.assign(node.dataset, value);
    else node.setAttribute(key, value);
  }
  if (text) node.textContent = text;
  return node;
}

function ensureUi(documentRef) {
  let palette = documentRef.getElementById('pmBuildCommandPalette');
  let dialog = documentRef.getElementById('pmBuildInfoDialog');

  if (!palette) {
    palette = element(documentRef, 'dialog', {
      id: 'pmBuildCommandPalette',
      className: 'pm-build-palette',
      'aria-labelledby': 'pmBuildCommandPaletteTitle'
    });
    const frame = element(documentRef, 'div', { className: 'pm-build-palette-frame' });
    const title = element(documentRef, 'h2', { id: 'pmBuildCommandPaletteTitle' }, 'Portmason commands');
    const command = element(documentRef, 'button', {
      type: 'button',
      className: 'pm-build-command',
      dataset: { pmBuildCommand: 'about' }
    });
    command.append(
      element(documentRef, 'span', { className: 'pm-build-command-title' }, 'About this build'),
      element(documentRef, 'small', {}, 'Release, build, deployment, and verification details')
    );
    const hint = element(documentRef, 'p', { className: 'pm-build-keyboard-hint' }, 'Esc closes this menu');
    frame.append(title, command, hint);
    palette.append(frame);
    documentRef.body.append(palette);
  }

  if (!dialog) {
    dialog = element(documentRef, 'dialog', {
      id: 'pmBuildInfoDialog',
      className: 'pm-build-dialog',
      'aria-labelledby': 'pmBuildInfoTitle'
    });
    const frame = element(documentRef, 'div', { className: 'pm-build-dialog-frame' });
    const toolbar = element(documentRef, 'header', { className: 'pm-build-dialog-toolbar' });
    toolbar.append(
      element(documentRef, 'strong', {}, 'Portmason Build Identity'),
      element(documentRef, 'button', {
        type: 'button',
        className: 'pm-build-close',
        'aria-label': 'Close build information',
        dataset: { pmBuildClose: 'true' }
      }, '×')
    );
    const body = element(documentRef, 'div', { className: 'pm-build-dialog-body' });
    body.append(
      element(documentRef, 'p', { className: 'pm-build-eyebrow' }, 'About this build'),
      element(documentRef, 'h2', { id: 'pmBuildInfoTitle' }, 'Build information'),
      element(documentRef, 'p', { className: 'pm-build-intro' }, 'These details identify the exact application artifact and deployment you are viewing.'),
      element(documentRef, 'p', { className: 'pm-build-status', id: 'pmBuildInfoStatus', role: 'status' }, 'Loading build information…'),
      element(documentRef, 'dl', { className: 'pm-build-grid', id: 'pmBuildInfoRows' })
    );
    const actions = element(documentRef, 'div', { className: 'pm-build-actions' });
    actions.append(
      element(documentRef, 'button', {
        type: 'button',
        className: 'pm-build-copy',
        dataset: { pmBuildCopy: 'true' }
      }, 'Copy details'),
      element(documentRef, 'button', {
        type: 'button',
        className: 'pm-build-done',
        dataset: { pmBuildClose: 'true' }
      }, 'Done')
    );
    body.append(actions);
    frame.append(toolbar, body);
    dialog.append(frame);
    documentRef.body.append(dialog);
  }

  return { palette, dialog };
}

function renderIdentity(documentRef, identity) {
  const rows = documentRef.getElementById('pmBuildInfoRows');
  const status = documentRef.getElementById('pmBuildInfoStatus');
  if (!rows || !status) return;

  rows.replaceChildren();
  for (const [label, value] of buildInfoRows(identity)) {
    rows.append(
      element(documentRef, 'dt', {}, label),
      element(documentRef, 'dd', {}, cleanString(value, 'Unavailable'))
    );
  }
  status.textContent = identity.verification === 'verified'
    ? 'Deployment metadata is verified.'
    : 'Build metadata loaded. Deployment verification is not recorded.';
}

function identityText(identity) {
  return buildInfoRows(identity).map(([label, value]) => `${label}: ${cleanString(value, 'Unavailable')}`).join('\n');
}

export function bindBuildInfo(options = {}) {
  const windowRef = options.windowRef || globalThis.window;
  const documentRef = options.documentRef || globalThis.document;
  if (!windowRef || !documentRef?.body) return () => {};
  if (windowRef.__PORTMASON_BUILD_INFO_BOUND__) return windowRef.PortmasonBuildInfo?.unbind || (() => {});

  const { palette, dialog } = ensureUi(documentRef);
  let lastTrigger = null;
  let currentIdentity = null;

  const openPalette = trigger => {
    lastTrigger = trigger || documentRef.activeElement;
    showDialog(palette);
    palette.querySelector('[data-pm-build-command="about"]')?.focus();
  };

  const openInfo = async trigger => {
    lastTrigger = trigger || documentRef.activeElement;
    closeDialog(palette);
    showDialog(dialog);
    documentRef.getElementById('pmBuildInfoStatus').textContent = 'Loading build information…';
    documentRef.getElementById('pmBuildInfoRows').replaceChildren();
    currentIdentity = await loadBuildIdentity({ ...options, windowRef, documentRef });
    renderIdentity(documentRef, currentIdentity);
    dialog.querySelector('[data-pm-build-close]')?.focus();
    windowRef.dispatchEvent?.(new CustomEvent('portmason:build-info-opened', { detail: currentIdentity }));
  };

  const restoreFocus = () => {
    if (lastTrigger?.isConnected && typeof lastTrigger.focus === 'function') lastTrigger.focus();
    lastTrigger = null;
  };

  const keyHandler = event => {
    if (!isBuildInfoShortcut(event)) return;
    event.preventDefault();
    openPalette(event.target);
  };

  const clickHandler = event => {
    const trigger = event.target?.closest?.('[data-pm-build-info-trigger]');
    if (trigger) {
      event.preventDefault();
      openInfo(trigger);
      return;
    }
    if (event.target?.closest?.('[data-pm-build-command="about"]')) {
      openInfo(event.target);
      return;
    }
    if (event.target?.closest?.('[data-pm-build-close]')) {
      closeDialog(dialog);
      restoreFocus();
      return;
    }
    if (event.target?.closest?.('[data-pm-build-copy]')) {
      if (!currentIdentity) return;
      const button = event.target.closest('[data-pm-build-copy]');
      const copyText = identityText(currentIdentity);
      Promise.resolve(windowRef.navigator?.clipboard?.writeText?.(copyText))
        .then(() => { button.textContent = 'Copied'; })
        .catch(() => { button.textContent = 'Copy unavailable'; })
        .finally(() => windowRef.setTimeout?.(() => { button.textContent = 'Copy details'; }, 1800));
    }
  };

  const cancelHandler = event => {
    event.preventDefault();
    closeDialog(event.currentTarget);
    restoreFocus();
  };

  documentRef.addEventListener('keydown', keyHandler);
  documentRef.addEventListener('click', clickHandler);
  palette.addEventListener('cancel', cancelHandler);
  dialog.addEventListener('cancel', cancelHandler);
  palette.addEventListener('close', restoreFocus);
  dialog.addEventListener('close', restoreFocus);

  const unbind = () => {
    documentRef.removeEventListener('keydown', keyHandler);
    documentRef.removeEventListener('click', clickHandler);
    palette.removeEventListener('cancel', cancelHandler);
    dialog.removeEventListener('cancel', cancelHandler);
    palette.removeEventListener('close', restoreFocus);
    dialog.removeEventListener('close', restoreFocus);
    windowRef.__PORTMASON_BUILD_INFO_BOUND__ = false;
  };

  windowRef.__PORTMASON_BUILD_INFO_BOUND__ = true;
  windowRef.PortmasonBuildInfo = { openPalette, open: openInfo, unbind };
  return unbind;
}

if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  const start = () => bindBuildInfo({ windowRef: window, documentRef: document });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
  else queueMicrotask(start);
}
