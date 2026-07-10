import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const indexPath = new URL('../www/index.html', import.meta.url);
const publicPath = new URL('../www/content/en-US/public.json', import.meta.url);

test('mobile layout puts the launch form before the hero without changing source order', async () => {
  const html = await readFile(indexPath, 'utf8');
  const heroIndex = html.indexOf('<div class="hero-copy">');
  const formIndex = html.indexOf('<section class="launch-card"');

  assert.ok(heroIndex > -1, 'hero copy exists');
  assert.ok(formIndex > -1, 'launch card exists');
  assert.ok(heroIndex < formIndex, 'desktop source order remains hero then form');
  assert.match(
    html,
    /@media\s*\(max-width:\s*640px\)[\s\S]*?\.launch-card\s*\{\s*order:\s*-1;\s*\}[\s\S]*?\.hero-copy\s*\{\s*order:\s*0;\s*\}/
  );
});

test('coming-soon status is explicit in the primary launch copy', async () => {
  const copy = JSON.parse(await readFile(publicPath, 'utf8'));

  assert.match(copy.meta.title, /Coming Soon/i);
  assert.match(copy.meta.description, /coming soon/i);
  assert.match(copy.hero.eyebrow, /coming soon/i);
  assert.match(copy.hero.title, /coming soon/i);
  assert.equal(copy.earlyAccess.kicker, 'Coming soon');
  assert.match(copy.earlyAccess.body, /not open yet/i);
  assert.match(copy.earlyAccess.submit, /launch list/i);
  assert.match(copy.footer.launch, /coming soon/i);
});

test('launch copy is clear and free of the prior early-access typo', async () => {
  const copy = JSON.parse(await readFile(publicPath, 'utf8'));
  const serialized = JSON.stringify(copy);

  assert.equal(copy.earlyAccess.emailLabel, 'Email for launch updates');
  assert.equal(copy.earlyAccess.assurance1, 'No card required to join');
  assert.doesNotMatch(serialized, /cerdit/i);
});
