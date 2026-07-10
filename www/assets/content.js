const CATALOG_FILES = ['public', 'notifications', 'errors'];
let catalog = Object.create(null);

function valueAtPath(source, path) {
  return String(path || '')
    .split('.')
    .filter(Boolean)
    .reduce((current, segment) => current?.[segment], source);
}

export function formatContent(value, variables = {}) {
  return String(value ?? '').replace(/\{([A-Za-z0-9_]+)\}/g, (match, key) => (
    Object.prototype.hasOwnProperty.call(variables, key)
      ? String(variables[key] ?? '')
      : match
  ));
}

export function copy(key, variables = {}, fallback = '') {
  const value = valueAtPath(catalog, key);
  const resolved = typeof value === 'string' || typeof value === 'number'
    ? String(value)
    : String(fallback ?? '');
  return formatContent(resolved, variables);
}

export function setContentCatalog(nextCatalog) {
  catalog = nextCatalog && typeof nextCatalog === 'object'
    ? nextCatalog
    : Object.create(null);
  return catalog;
}

export async function loadContentCatalog(options = {}) {
  const locale = options.locale || 'en-US';
  const fetchFn = options.fetchFn || globalThis.fetch;
  const baseUrl = options.baseUrl || new URL(`../content/${locale}/`, import.meta.url);

  if (typeof fetchFn !== 'function') {
    throw new TypeError('A fetch implementation is required to load the content catalog.');
  }

  const entries = await Promise.all(CATALOG_FILES.map(async name => {
    const response = await fetchFn(new URL(`${name}.json`, baseUrl));
    if (!response?.ok) {
      throw new Error(`Unable to load content catalog file: ${name}.json`);
    }
    return [name, await response.json()];
  }));

  return setContentCatalog(Object.fromEntries(entries));
}

export function applyContent(root = globalThis.document) {
  if (!root?.querySelectorAll) return 0;

  let applied = 0;
  root.querySelectorAll('[data-copy]').forEach(element => {
    const key = element.getAttribute('data-copy');
    const value = copy(key);
    const attribute = element.getAttribute('data-copy-attr');

    if (attribute) {
      element.setAttribute(attribute, value);
    } else if (element.hasAttribute('data-copy-html')) {
      element.innerHTML = value;
    } else {
      element.textContent = value;
    }
    applied += 1;
  });

  return applied;
}
