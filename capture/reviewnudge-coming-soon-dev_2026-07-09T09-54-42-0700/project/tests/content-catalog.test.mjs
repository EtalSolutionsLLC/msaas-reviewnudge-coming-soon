import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../', import.meta.url);
const indexPath = new URL('../www/index.html', import.meta.url);
const publicPath = new URL('../www/content/en-US/public.json', import.meta.url);
const notificationsPath = new URL('../www/content/en-US/notifications.json', import.meta.url);
const errorsPath = new URL('../www/content/en-US/errors.json', import.meta.url);

function get(source, path) {
  return path.split('.').reduce((current, segment) => current?.[segment], source);
}

test('content catalogs are valid and every HTML copy key resolves', async () => {
  const [html, publicCopy, notifications, errors] = await Promise.all([
    readFile(indexPath, 'utf8'),
    readFile(publicPath, 'utf8').then(JSON.parse),
    readFile(notificationsPath, 'utf8').then(JSON.parse),
    readFile(errorsPath, 'utf8').then(JSON.parse)
  ]);
  const catalog = { public: publicCopy, notifications, errors };
  const keys = [...html.matchAll(/data-copy="([^"]+)"/g)].map(match => match[1]);
  assert.ok(keys.length > 40, 'page should be driven by the content catalog');
  for (const key of keys) {
    assert.notEqual(get(catalog, key), undefined, `missing content key: ${key}`);
  }
});

test('index.html contains structure and content keys, not visitor-facing prose', async () => {
  const html = await readFile(indexPath, 'utf8');
  const body = html.slice(html.indexOf('<body'), html.indexOf('</body>'))
    .replace(/<svg[\s\S]*?<\/svg>/g, '')
    .replace(/<script[\s\S]*?<\/script>/g, '')
    .replace(/<[^>]+>/g, '')
    .replace(/[✓★\s]+/g, '');
  assert.equal(body, '');
  assert.doesNotMatch(html, /A thoughtful nudge|Be first in line|Notify me|Today’s nudges/);
});

test('waitlist timing and outcomes live in JSON rather than browser logic', async () => {
  const [notifications, errors, js] = await Promise.all([
    readFile(notificationsPath, 'utf8').then(JSON.parse),
    readFile(errorsPath, 'utf8').then(JSON.parse),
    readFile(new URL('../www/assets/waitlist.js', import.meta.url), 'utf8')
  ]);
  assert.equal(notifications.waitlist.submitting, 'Adding you to the early access list… This usually takes 10–15 seconds.');
  assert.match(errors.waitlist.verificationFailed, /\{traceId\}/);
  assert.doesNotMatch(js, /Adding you to the early access list|Please enter a valid email address|You’re on the list/);
});
