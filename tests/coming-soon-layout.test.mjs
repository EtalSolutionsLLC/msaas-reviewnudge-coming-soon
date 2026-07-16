import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const indexPath = new URL('../www/index.html', import.meta.url);
const publicPath = new URL('../www/content/en-US/public.json', import.meta.url);

test('mobile layout puts the launch card before the hero without changing source order', async () => {
  const html = await readFile(indexPath, 'utf8');
  const heroIndex = html.indexOf('<div class="hero-copy">');
  const cardIndex = html.indexOf('<section class="launch-card"');

  assert.ok(heroIndex > -1, 'hero copy exists');
  assert.ok(cardIndex > -1, 'launch card exists');
  assert.ok(heroIndex < cardIndex, 'desktop source order remains hero then launch card');
  assert.match(
    html,
    /@media\s*\(max-width:\s*640px\)[\s\S]*?\.launch-card\s*\{\s*order:\s*-1;\s*\}[\s\S]*?\.hero-copy\s*\{\s*order:\s*0;\s*\}/
  );
});

test('international launch update acknowledges the prior date and names the new date', async () => {
  const copy = JSON.parse(await readFile(publicPath, 'utf8'));

  assert.match(copy.meta.title, /July 20/i);
  assert.match(copy.meta.description, /internationally Monday, July 20/i);
  assert.equal(copy.hero.title, 'ReviewNudge launches internationally Monday.');
  assert.match(copy.hero.body, /July 15 launch date has passed/i);
  assert.match(copy.hero.body, /first language isn’t English/i);
  assert.equal(copy.launch.title, 'Monday, July 20, 2026');
  assert.match(copy.launch.messageItem3, /opens Monday, July 20/i);
});

test('launch explanation is concise, reassuring, and not apologetic', async () => {
  const copy = JSON.parse(await readFile(publicPath, 'utf8'));
  const serialized = JSON.stringify(copy);

  assert.match(copy.launch.body, /won’t have to wait long/i);
  assert.equal(copy.launch.messageTitle, 'What changed?');
  assert.equal(copy.nav.join, 'July 20');
  assert.equal(copy.hero.secondary, 'Launching July 20');
  assert.equal(copy.preview.cta, 'Launching July 20');
  assert.doesNotMatch(serialized, /\b(?:sorry|apolog(?:y|ize|ise|etic))\b/i);
});
