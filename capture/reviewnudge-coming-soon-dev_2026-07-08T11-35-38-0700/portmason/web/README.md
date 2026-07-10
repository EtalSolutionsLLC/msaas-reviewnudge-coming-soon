# Portmason browser utilities

`pm-viewport-navigation.js` is the canonical viewport-navigation contract for Portmason product and corporate sites.

It exports:

- `getViewportFrame()`
- `calculateTargetScrollTop()`
- `alignViewportTarget()`
- `navigateToHash()`
- `bindViewportNavigation()`

The contract centers a requested section within the usable viewport below the sticky header. Content taller than the usable viewport is aligned beneath the header. Reduced-motion preferences are honored.
