# Phase 1 architecture

## Runtime

One Swift 6 macOS application, deployment target macOS 14. SwiftUI owns navigation, the main window, a settings window and MenuBarExtra; AppKit handles activation and application lifetime. Closing the window does not quit the menu bar process. Only implemented functionality is exposed.

`AppEnvironment` is the composition root. It owns one `ModelContainer`, one main-actor `ModelContext` and the services. `AppBootstrap` shows a recoverable Russian startup error if the database cannot open; it never deletes data or silently falls back to volatile storage. Hosted tests use in-memory bootstrap storage.

Views read SwiftData using `@Query`; writes pass through stores. The manual analysis view model owns cancellation and request state. Persistence and Keychain run on the main actor; asynchronous network requests do not block UI rendering. Providers and domain result values are Sendable. There are no external packages.

## Local storage

One SwiftData schema contains `VocabularyEntry`, `AnalysisHistoryEntry` and `AppSettings`. CloudKit is explicitly disabled. Autosave is disabled so store operations have explicit save/error boundaries. History and encounter updates commit together; failed transactions roll back.

Normalization applies canonical Unicode composition, French lowercasing, whitespace collapse and apostrophe equivalence. It deliberately preserves accents, ligatures, hyphens and punctuation; `a`/`à`, `ou`/`où` and `peut-être`/`peut être` stay distinct. The normalized expression is unique. Repeat encounters increment the count and merge missing metadata without replacing spelling, original source, saved status or notes. Saving is idempotent and does not increment encounter counts.

History contains a validated structured analysis, not the original prompt or arbitrary clipboard text. When automatic history is off, manual analyses are not persisted unless the user saves them. Clearing history also removes unsaved encounters, retaining saved expressions and their notes.

Specialized command-query and conversation records will be introduced in their owning phases, when their fields and behavior become useful. The shared source enum already identifies the four integrations plus phase 1 manual analysis. No unused service skeletons are included.

## AI boundary

`LanguageAnalysisService` resolves the saved provider/model and retrieves the key for each request. `LanguageModelProvider` is the vendor-independent asynchronous interface. `OpenAIProvider` is its only current implementation; settings expose the provider and an editable model ID without offering unsupported providers.

The provider uses Responses API with `text.format.type = json_schema`, `strict = true` and `store = false`. The shared schema is copied directly into the application bundle by Xcode, without a duplicate Swift schema. Nullable fields are required but can be null. Refusals, incomplete output, malformed data, authorization errors, limits and network errors map to conservative Russian messages. The app does not expose raw server errors. Connection testing exercises the same model/schema path using `bonjour` and does not persist the result.

The default is `gpt-4o-mini`, a model documented as supporting Structured Outputs. Model availability depends on the user's account. API contract reference: [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs). Current implementation was checked against this documentation on 2026-09-06.

Keychain uses a non-synchronizing generic password accessible when the device is unlocked. The app never stores the provider key in preferences or its database. URLSession is ephemeral, has no disk cache or cookies, and refuses redirects. Only the official HTTPS endpoint can receive the authorization header.

## Scope boundaries

Phase 2 introduces the global shortcut, NSPanel, cache, speech and follow-up. Phase 3 introduces opt-in pasteboard handling. Phase 4 introduces an authenticated loopback bridge. Phase 5 implements Chrome. Phase 6 adds mini-dialogues. Phase 7 polishes onboarding, permissions and visual consistency.

There is no listener, pasteboard monitor, speech capture, telemetry, authentication, cloud database or production mock in phase 1. The app sandbox currently grants only outbound network access. New permissions must be added only with their owning feature.
