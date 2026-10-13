/**
 * Portmason viewport navigation contract.
 *
 * Centers a requested section inside the usable viewport below a sticky header.
 * Sections taller than the usable viewport are aligned immediately below the
 * header instead of being awkwardly centered.
 */

function resolveElement(value, documentRef) {
  if (!value) return null;
  if (typeof value === 'string') return documentRef?.querySelector(value) || null;
  return value;
}

function elementHeight(element, windowRef, { stickyOnly = false } = {}) {
  if (!element || element.hidden) return 0;
  if (stickyOnly && windowRef?.getComputedStyle) {
    const position = windowRef.getComputedStyle(element).position;
    if (position !== 'sticky' && position !== 'fixed') return 0;
  }
  const rect = element.getBoundingClientRect?.();
  return Math.max(0, Number(rect?.height || 0));
}

export function getViewportFrame(options = {}) {
  const windowRef = options.windowRef || globalThis.window;
  const documentRef = options.documentRef || globalThis.document;
  const header = resolveElement(options.header || options.headerSelector || '[data-pm-sticky-header]', documentRef);
  const footer = resolveElement(options.footer || options.footerSelector || '[data-pm-footer]', documentRef);
  const viewportHeight = Math.max(0, Number(options.viewportHeight ?? windowRef?.innerHeight ?? 0));
  const headerHeight = Math.max(0, Number(options.headerHeight ?? elementHeight(header, windowRef, { stickyOnly: true })));
  const footerHeight = options.includeFooter
    ? Math.max(0, Number(options.footerHeight ?? elementHeight(footer, windowRef)))
    : 0;
  const usableHeight = Math.max(0, viewportHeight - headerHeight - footerHeight);
  const frame = {
    viewportHeight,
    headerHeight,
    footerHeight,
    usableHeight,
    top: headerHeight,
    bottom: viewportHeight - footerHeight
  };

  const style = documentRef?.documentElement?.style;
  style?.setProperty('--pm-header-h', `${headerHeight}px`);
  style?.setProperty('--pm-footer-h', `${footerHeight}px`);
  style?.setProperty('--pm-usable-vh', `${usableHeight}px`);

  return frame;
}

export function calculateTargetScrollTop({
  targetTop,
  targetHeight,
  currentScrollY = 0,
  frame
}) {
  if (!frame) throw new TypeError('frame is required');
  const absoluteTop = Number(currentScrollY) + Number(targetTop);
  const height = Math.max(0, Number(targetHeight));

  if (height >= frame.usableHeight) {
    return Math.max(0, Math.round(absoluteTop - frame.top));
  }

  const centeredOffset = frame.top + ((frame.usableHeight - height) / 2);
  return Math.max(0, Math.round(absoluteTop - centeredOffset));
}

export function alignViewportTarget(targetOrSelector, options = {}) {
  const windowRef = options.windowRef || globalThis.window;
  const documentRef = options.documentRef || globalThis.document;
  const target = resolveElement(targetOrSelector, documentRef);
  if (!target || target.hidden || !windowRef) return false;

  const rect = target.getBoundingClientRect?.();
  if (!rect) return false;

  const frame = getViewportFrame({ ...options, windowRef, documentRef });
  const top = calculateTargetScrollTop({
    targetTop: rect.top,
    targetHeight: rect.height,
    currentScrollY: windowRef.scrollY || windowRef.pageYOffset || 0,
    frame
  });

  const reducedMotion = options.reducedMotion ?? windowRef.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
  windowRef.scrollTo({
    top,
    behavior: reducedMotion || options.behavior === 'auto' ? 'auto' : (options.behavior || 'smooth')
  });
  return { target, top, frame };
}

function normalizeHash(hash) {
  if (!hash) return '';
  return hash.startsWith('#') ? hash : `#${hash}`;
}

function queueAlignment(callback, windowRef) {
  const raf = windowRef?.requestAnimationFrame?.bind(windowRef);
  if (!raf) {
    callback();
    return;
  }
  raf(() => raf(callback));
}

export function navigateToHash(hash, options = {}) {
  const windowRef = options.windowRef || globalThis.window;
  const documentRef = options.documentRef || globalThis.document;
  const normalizedHash = normalizeHash(hash);
  if (!normalizedHash || !windowRef || !documentRef) return false;

  const id = decodeURIComponent(normalizedHash.slice(1));
  const target = documentRef.getElementById(id);
  if (!target || target.hidden) return false;

  if (options.updateHistory !== false) {
    const method = options.replace ? 'replaceState' : 'pushState';
    const nextUrl = `${windowRef.location.pathname}${windowRef.location.search}${normalizedHash}`;
    if (windowRef.location.hash !== normalizedHash || options.replace) {
      windowRef.history?.[method]?.({}, '', nextUrl);
    }
  }

  queueAlignment(() => alignViewportTarget(target, { ...options, windowRef, documentRef }), windowRef);
  return true;
}

export function bindViewportNavigation(root = globalThis.document, options = {}) {
  const documentRef = options.documentRef || root?.ownerDocument || root || globalThis.document;
  const windowRef = options.windowRef || documentRef?.defaultView || globalThis.window;
  if (!root?.addEventListener || !documentRef || !windowRef) return () => {};

  const clickHandler = event => {
    const link = event.target?.closest?.('a[href*="#"]');
    if (!link || !root.contains?.(link)) return;

    const url = new URL(link.href, windowRef.location.href);
    const sameDocument = url.origin === windowRef.location.origin
      && url.pathname === windowRef.location.pathname
      && url.search === windowRef.location.search;
    if (!sameDocument || !url.hash) return;

    const target = documentRef.getElementById(decodeURIComponent(url.hash.slice(1)));
    if (!target || target.hidden) return;

    event.preventDefault();
    navigateToHash(url.hash, { ...options, windowRef, documentRef });
  };

  const hashHandler = () => {
    if (windowRef.location.hash) {
      navigateToHash(windowRef.location.hash, {
        ...options,
        windowRef,
        documentRef,
        updateHistory: false
      });
    }
  };

  root.addEventListener('click', clickHandler);
  windowRef.addEventListener?.('hashchange', hashHandler);

  getViewportFrame({ ...options, windowRef, documentRef });
  if (windowRef.location.hash) hashHandler();

  return () => {
    root.removeEventListener('click', clickHandler);
    windowRef.removeEventListener?.('hashchange', hashHandler);
  };
}
