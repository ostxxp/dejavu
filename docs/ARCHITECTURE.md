# DéjàVu architecture — phases 1–4

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

Phase 2 implements the global shortcut, NSPanel, cache, speech and follow-up. Phase 3 implements opt-in pasteboard handling. Phase 4 implements an authenticated loopback bridge. Phase 5 implements Chrome. Phase 6 adds mini-dialogues. Phase 7 polishes onboarding, permissions and visual consistency.

There is no speech capture, telemetry, user-account authentication, cloud database or production mock. The app sandbox grants outbound network access and, from phase 4, inbound networking for the loopback listener. New permissions must be added only with their owning feature.

## Quick assistant

`CommandPaletteController` owns one lazily constructed, nonactivating floating `NSPanel`. It preserves the foreground application, uses the pointer's screen and clamps its frame to the visible area. Escape and losing key status hide the panel and cancel speech/network work. `GlobalShortcut` registers only Command–Shift–physical F through Carbon, without monitoring other keys or requesting Accessibility permission. Registration conflicts are visible and retryable in Settings; macOS releases registration on process exit.

`CommandPaletteModel` owns request cancellation, one follow-up, draft-preserving query navigation and UI state. Request identities prevent late completions from changing cleared state. A settings revision prevents history persistence after an off/on toggle during an outstanding request. Clearing history also clears panel state and the response cache. Hosted tests do not register global shortcuts.

`AnalysisRequest` carries text plus at most one validated `FollowUpContext`. The provider sends a follow-up as explicit user/assistant/user text turns, retaining `store: false`, without provider-side conversation identifiers. The last turn asks the new question. Nullable metadata is normalized so literal null strings are not shown. Reference: [OpenAI conversation state](https://developers.openai.com/api/docs/guides/conversation-state).

`LanguageAnalysisService` shares an in-memory LRU cache between the main window and panel: 100 results, fixed 30-minute lifetime. Identity includes provider, model, trimmed query and full context, preserving accents and case. Refresh bypasses cache; clearing advances a generation so outstanding requests cannot repopulate a cleared cache. Connection checks bypass it. It is never serialized to disk.

`SpeechService` uses `AVSpeechSynthesizer` with an installed fr-FR voice, stopping prior speech before a new utterance. Missing voice availability produces a Russian error. No microphone permission or third-party speech API is involved.

## Clipboard analysis

`ClipboardMonitor` checks `NSPasteboard.changeCount` every 600 ms only while enabled. It establishes the current count as a baseline without reading the existing contents. One stable interval debounces new changes. A change invalidates prior work immediately; a second count check after reading rejects a clipboard replaced during the read. The system adapter rejects concealed/transient/generated markers, files and copies originating from DéjàVu. Tests use a private named pasteboard, never the user's general clipboard.

`ClipboardPolicy` enforces bounded input (4,000 characters / 24 KB), excludes common credentials and technical content, then requires French to be the dominant language with confidence at least 0.8 from unconstrained `NLLanguageRecognizer`. No language hints force a French classification. This intentionally misses some ambiguous short words and cannot identify all sensitive prose. A bounded in-memory SHA256 set suppresses repeats for ten minutes. No arbitrary clipboard value or hash is persisted.

`ClipboardModel` keeps only the current eligible candidate, requiring confirmation unless auto-analysis is enabled and the text is at most 500 characters. It reuses the shared service/cache and stores only successful structured analysis with the clipboard source, never a command-query record. Both global and clipboard history switches apply. Request identities, cancellation and setting revisions prevent late results from appearing or being saved after disabling. Any clipboard option change stops reading and cancels current work; persistence failures leave monitoring stopped and display an error.

`ClipboardPanelController` owns one nonactivating panel. Presentation does not make it key; controls may take focus on deliberate interaction. New content replaces old content, with bounded scrolling and detailed view. The panel expires after 20 seconds for results or 60 seconds for candidates/errors, paused while hovered or loading. Expiration releases candidate/result memory even when popup display is disabled. A menu action can reveal current content while available. Settings fields have migration defaults: disabled, no automatic upload, panel enabled, clipboard history enabled (still subject to global history).

Native references: [NSPasteboard.changeCount](https://developer.apple.com/documentation/appkit/nspasteboard/changecount), [NLLanguageRecognizer](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer). Checked against Apple documentation during phase 3.

## Browser bridge

`LocalHTTPServer` uses Network.framework with `requiredLocalEndpoint` explicitly set to IPv4 `127.0.0.1`, fixed production port 17389. No Bonjour service, wildcard bind or LAN interface is used. The incoming peer is checked as IPv4 loopback too. It supports a single bounded HTTP/1.1 request per connection, at most 16 connections, a ten-second read deadline and a 95-second operation deadline. Disconnect/disable cancels request tasks. `BridgeHTTPParser` rejects duplicate headers, transfer encoding, missing POST lengths, oversized headers/bodies and pipelined bytes.

`BridgeRouter` is separate from transport so a future Native Messaging adapter can reuse application operations. The literal Host must match the loopback address and port. Every operation, including health, requires a bearer pairing code. Browser Origin must exactly match the configured extension ID; there is no wildcard CORS. An originless native client still needs authentication. Only the matching extension receives unauthenticated preflight responses, which contain no application data.

`BrowserBridge` generates a 256-bit random token with SecRandomCopyBytes and stores it under a separate Keychain service/account. Provider credentials retain their existing service and account. Starting, disabling or rotating the bridge invalidates issued results and pending requests; it never logs headers, input, results or codes. Clearing history also invalidates pending/issued bridge results. The UI only reveals a pairing code after a deliberate action and clears it on disappearance or stop. Clipboard copies carry a concealed marker.

Analyze uses the common LanguageAnalysisService and cache, with at most two concurrent analyses and 20 accepted analysis requests per minute. Responses carry a temporary UUID plus the shared structured analysis. Save accepts only such a UUID, never an arbitrary client-supplied analysis. The issued-analysis store is memory-only, bounded to 100 entries with a 30-minute lifetime. Successful history uses the Chrome selection source and respects the global history setting/revision. Provider failures become conservative Russian JSON errors.

References: [NWParameters.requiredLocalEndpoint](https://developer.apple.com/documentation/network/nwparameters/requiredlocalendpoint), [NWListener](https://developer.apple.com/documentation/network/nwlistener), [SecRandomCopyBytes](https://developer.apple.com/documentation/security/secrandomcopybytes(_:_:_:)).

## Chrome extension

Manifest V3 uses a module service worker, a top-frame isolated content script and a closed Shadow DOM. Selection detection uses the browser language detector with a small explicit whitelist for short French expressions. Only a trusted click sends the selected text to the local bridge. Input/editable/code selections are excluded. DOM rendering uses textContent and element creation, without HTML interpolation.

The service worker owns local pairing storage, restricted to TRUSTED_CONTEXTS before processing messages; content scripts receive only public configuration. Popup operations require the exact extension popup URL. Page operations require the extension sender ID, a top-level HTTP(S) document and enabled domain policy. Save/listen IDs are scoped to tab and document, bounded and expire after 30 minutes. Session updates are serialized to preserve concurrent results. Cancellation, transport timeout and configuration rechecks suppress late responses.

French speech uses a local Chrome TTS voice. The native app registers dejavu://open for the popup link. No provider key, complete page content, remote assets or analytics enter the extension. See chrome-extension/README.md for storage and permission details.

## Mini-dialogues

DialogueService uses the same OpenAI Responses transport and keychain as analysis, with separate strict scenario and feedback schemas. DialogueModel owns a single cancellable interaction, rotates 15 contexts and keeps at most 20 generated questions in memory. User answers and audio are never persisted. An explicit useful-phrase save creates a normal vocabulary entry with the conversationGhost source; it works independently of global history. Clearing history also clears dialogue memory and cancels work.

DialogueController polls eligibility every 15 seconds, with an interval plus up to 20% jitter. It checks session state, idle duration, wake cooldown, full-screen bounds, mirrored screens, known meeting/presentation applications and existing helpers. No pixel capture, screen-recording permission or accessibility permission is requested. These interruption checks are heuristics, not a reliable screen-sharing/Focus detector. A nonactivating NSPanel uses visible screen bounds; an explicit trial can take focus. Pauses and schedule preferences have migration defaults in AppSettings.

DialogueVoice requests Speech and microphone permissions only after explicit action, requires local fr-FR support, limits recording to 60 seconds and presents editable text before AI submission. Generation IDs prevent a delayed permission/recognition callback from restarting or filling a closed interaction. Unsupported on-device recognition falls back to typing, never silently uploads audio. See PHASE_6.md for verification limits and API references.
