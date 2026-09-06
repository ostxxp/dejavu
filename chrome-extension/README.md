# Chrome companion — phase 5

The extension is intentionally not implemented in phase 1. This directory records its scope, not a runnable extension.

It will be a Manifest V3 integration using TypeScript, a content script, a service worker and Shadow DOM. All visible text will be Russian. The macOS app owns analysis, vocabulary, history and settings. The extension may store only the local pairing token, never an AI provider key or a copy of the learning database.

Phase 4 must first provide an authenticated bridge bound exclusively to `127.0.0.1`. Phase 5 then adds selection detection, an explicit action bubble, safe text rendering and pairing. See `../docs/PRODUCT_SPEC.md` for the complete specification.
