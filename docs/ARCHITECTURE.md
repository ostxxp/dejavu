# DéjàVu architecture — phases 1–2

## Runtime

One Swift 6 macOS application, deployment target macOS 14. SwiftUI owns navigation, the main window, a settings window and MenuBarExtra; AppKit handles activation and application lifetime. Closing the window does not quit the menu bar process. Only implemented functionality is exposed.

`AppEnvironment` is the composition root. It owns one `ModelContainer`, one main-actor `ModelContext` and the services. `AppBootstrap` shows a recoverable Russian startup error if the database cannot open; it never deletes data or silently falls back to volatile storage. Hosted tests use in-memory bootstrap storage.

Views read SwiftData using `@Query`; writes pass through stores. The manual analysis view model owns cancellation and request state. Persistence and Keychain run on the main actor; asynchronous network requests do not block UI rendering. Providers and domain result values are Sendable. There are no external packages.

## Local storage

One SwiftData schema contains `VocabularyEntry`, `AnalysisHistoryEntry`, `CommandPaletteHistoryEntry` and `AppSettings`. CloudKit is explicitly disabled. Autosave is disabled so store operations have explicit save/error boundaries. History and encounter updates commit together; failed transactions roll back.

Normalization applies canonical Unicode composition, French lowercasing, whitespace collapse and apostrophe equivalence. It deliberately preserves accents, ligatures, hyphens and punctuation; `a`/`à`, `ou`/`où` and `peut-être`/`peut être` stay distinct. The normalized expression is unique. Repeat encounters increment the count and merge missing metadata without replacing spelling, original source, saved status or notes. Saving is idempotent and does not increment encounter counts.

Analysis history contains a validated structured analysis. Command history separately retains the successful query and, for a follow-up, one bounded context snapshot. When automatic history is off, manual analyses are not persisted unless the user saves them. Clearing history also removes unsaved encounters, retaining saved expressions and their notes.

Command history deduplicates by a SHA256 fingerprint, retains the latest 100 successful requests, and commits in the same transaction as analysis history and encounters. A disk-backed migration test opens the phase 1 schema with the added model. Conversation records remain deferred. The shared source enum already identifies the four integrations plus phase 1 manual analysis. No unused service skeletons are included.

## AI boundary

`LanguageAnalysisService` resolves the saved provider/model and retrieves the key for each request. `LanguageModelProvider` is the vendor-independent asynchronous interface. `OpenAIProvider` is its only current implementation; settings expose the provider and an editable model ID without offering unsupported providers.

The provider uses Responses API with `text.format.type = json_schema`, `strict = true` and `store = false`. The shared schema is copied directly into the application bundle by Xcode, without a duplicate Swift schema. Nullable fields are required but can be null. Refusals, incomplete output, malformed data, authorization errors, limits and network errors map to conservative Russian messages. The app does not expose raw server errors. Connection testing exercises the same model/schema path using `bonjour` and does not persist the result.

The default is `gpt-4o-mini`, a model documented as supporting Structured Outputs. Model availability depends on the user's account. API contract reference: [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs). Current implementation was checked against this documentation on 2026-09-06.

Keychain uses a non-synchronizing generic password accessible when the device is unlocked. The app never stores the provider key in preferences or its database. URLSession is ephemeral, has no disk cache or cookies, and refuses redirects. Only the official HTTPS endpoint can receive the authorization header.

## Scope boundaries

Phase 2 implements the global shortcut, NSPanel, cache, speech and follow-up. Phase 3 introduces opt-in pasteboard handling. Phase 4 introduces an authenticated loopback bridge. Phase 5 implements Chrome. Phase 6 adds mini-dialogues. Phase 7 polishes onboarding, permissions and visual consistency.

There is no listener, pasteboard monitor, speech capture, telemetry, authentication, cloud database or production mock. The app sandbox currently grants only outbound network access. New permissions must be added only with their owning feature.

## Quick assistant

`CommandPaletteController` owns one lazily constructed, nonactivating floating `NSPanel`. It preserves the foreground application, uses the pointer's screen and clamps its frame to the visible area. Escape and losing key status hide the panel and cancel speech/network work. `GlobalShortcut` registers only Command–Shift–physical F through Carbon, without monitoring other keys or requesting Accessibility permission. Registration conflicts are visible and retryable in Settings; macOS releases registration on process exit.

`CommandPaletteModel` owns request cancellation, one follow-up, draft-preserving query navigation and UI state. Request identities prevent late completions from changing cleared state. A settings revision prevents history persistence after an off/on toggle during an outstanding request. Clearing history also clears panel state and the response cache. Hosted tests do not register global shortcuts.

`AnalysisRequest` carries text plus at most one validated `FollowUpContext`. The provider sends a follow-up as explicit user/assistant/user text turns, retaining `store: false`, without provider-side conversation identifiers. The last turn asks the new question. Nullable metadata is normalized so literal null strings are not shown. Reference: [OpenAI conversation state](https://developers.openai.com/api/docs/guides/conversation-state).

`LanguageAnalysisService` shares an in-memory LRU cache between the main window and panel: 100 results, fixed 30-minute lifetime. Identity includes provider, model, trimmed query and full context, preserving accents and case. Refresh bypasses cache; clearing advances a generation so outstanding requests cannot repopulate a cleared cache. Connection checks bypass it. It is never serialized to disk.

`SpeechService` uses `AVSpeechSynthesizer` with an installed fr-FR voice, stopping prior speech before a new utterance. Missing voice availability produces a Russian error. No microphone permission or third-party speech API is involved.
