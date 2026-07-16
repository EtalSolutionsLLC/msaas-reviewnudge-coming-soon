import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { Buffer } from 'node:buffer';

const root = new URL('../', import.meta.url);
const expectedLocales = ['en-US', 'zh-CN', 'hi-IN', 'es-ES', 'ar', 'fr-FR', 'bn-BD', 'pt-BR', 'id-ID', 'ur-PK'];
const catalogNames = ['public', 'notifications', 'errors'];

function leafPaths(value, prefix = '') {
  return Object.entries(value).flatMap(([key, child]) => {
    const path = prefix ? `${prefix}.${key}` : key;
    return child && typeof child === 'object' && !Array.isArray(child)
      ? leafPaths(child, path)
      : [path];
  }).sort();
}

test('language picker sits beside the logo and offers exactly ten languages', async () => {
  const html = await readFile(new URL('../www/index.html', import.meta.url), 'utf8');
  const logo = html.indexOf('class="product-lockup"');
  const picker = html.indexOf('class="language-picker"');
  const nav = html.indexOf('class="public-nav"');
  const options = [...html.matchAll(/<option value="([^"]+)"/g)].map(match => match[1]);

  assert.ok(logo > -1 && picker > logo && nav > picker, 'picker follows the logo and precedes navigation');
  assert.deepEqual(options, expectedLocales);
  assert.match(html, /🌐/);
});

test('browser language detection, cookie override, and RTL metadata are deterministic', async () => {
  const source = await readFile(new URL('../www/assets/language.js', import.meta.url), 'utf8');
  const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;
  const language = await import(moduleUrl);

  assert.deepEqual(language.SUPPORTED_LOCALES.map(item => item.locale), expectedLocales);
  assert.equal(language.resolveLocale({ navigatorLanguages: ['de-DE', 'es-MX'] }), 'es-ES');
  assert.equal(language.resolveLocale({ cookieLocale: 'fr-FR', navigatorLanguages: ['hi-IN'] }), 'fr-FR');
  assert.equal(language.resolveLocale({ navigatorLanguages: ['zh-Hant-TW'] }), 'zh-CN');
  assert.equal(language.resolveLocale({ navigatorLanguages: ['de-DE'] }), 'en-US');
  assert.equal(language.readLocaleCookie('theme=dark; reviewnudge_language=ur-PK'), 'ur-PK');
  assert.match(language.createLocaleCookie('pt-BR', { secure: true }), /Max-Age=31536000; Path=\/; SameSite=Lax; Secure$/);
  assert.equal(language.localeDefinition('ar').direction, 'rtl');
  assert.equal(language.localeDefinition('ur-PK').direction, 'rtl');
});

test('every supported locale has complete public, notification, and error catalogs', async () => {
  const contentRoot = new URL('../www/content/', import.meta.url);
  const folders = (await readdir(contentRoot, { withFileTypes: true }))
    .filter(entry => entry.isDirectory())
    .map(entry => entry.name)
    .sort();
  assert.deepEqual(folders, [...expectedLocales].sort());

  for (const catalogName of catalogNames) {
    const baseline = JSON.parse(await readFile(new URL(`../www/content/en-US/${catalogName}.json`, import.meta.url), 'utf8'));
    const expectedPaths = leafPaths(baseline);

    for (const locale of expectedLocales) {
      const localized = JSON.parse(await readFile(new URL(`../www/content/${locale}/${catalogName}.json`, import.meta.url), 'utf8'));
      assert.deepEqual(leafPaths(localized), expectedPaths, `${locale}/${catalogName}.json must match the English schema`);
      for (const value of Object.values(localized).flatMap(section => Object.values(section))) {
        assert.notEqual(String(value).trim(), '', `${locale}/${catalogName}.json contains an empty value`);
      }
    }
  }
});

test('site bootstrap applies the resolved locale and persists manual changes', async () => {
  const site = await readFile(new URL('../www/assets/site.js', import.meta.url), 'utf8');
  assert.match(site, /readLocaleCookie\(document\.cookie\)/);
  assert.match(site, /window\.navigator\.languages/);
  assert.match(site, /loadContentCatalog\(\{ locale \}\)/);
  assert.match(site, /languageSelect\?\.addEventListener\('change'/);
  assert.match(site, /setLocaleCookie\(activeLocale, document, window\.location\)/);
  assert.match(site, /applyLocaleMetadata\(locale, document\)/);
});
