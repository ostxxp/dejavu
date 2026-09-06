You are a senior macOS engineer, Swift engineer, Chrome Extension engineer, product designer, and pragmatic software architect.

Your task is to build from scratch a polished personal French-learning application called **DéjàVu**.

You are working inside an EMPTY project folder.

Create the entire repository and application architecture from scratch.

Do not ask me to create files manually unless technically unavoidable.

Do not ask broad product questions.

Make sensible engineering decisions yourself.

If something is ambiguous, choose the simplest robust implementation that matches this specification.

The goal is not to generate a giant prototype. The goal is to build a real, working application incrementally.

==================================================
PRODUCT IDEA
============

DéjàVu is a native macOS French-learning assistant that integrates French practice into normal computer use.

It is designed primarily for a Russian-speaking learner around A2 level progressing toward B1.

The product should not feel like Duolingo, a textbook, or a generic chatbot.

It should feel like a lightweight premium macOS utility:

Raycast / Spotlight / Arc-like simplicity,
but specifically for learning French.

DéjàVu should help the learner:

1. encounter French,
2. understand it instantly,
3. save useful expressions,
4. encounter them again,
5. actively use them.

The application contains four main features:

1. **Разбор выделенного текста**
   Internal name: French Popup

2. **Разбор скопированного**
   Internal name: French Clipboard

3. **Быстрый помощник**
   Internal name: French Command Palette

4. **Мини-диалоги**
   Internal name: Conversation Ghost

These are NOT four separate applications.

They must share:

* one vocabulary database,
* one history,
* one AI layer,
* one settings system,
* one design language,
* one macOS application.

The Chrome integration is only a companion extension.

==================================================
IMPORTANT UI LANGUAGE RULE
==========================

ALL USER-FACING INTERFACE TEXT MUST BE IN RUSSIAN.

This includes:

* buttons,
* navigation,
* settings,
* onboarding,
* errors,
* menus,
* empty states,
* help text,
* notifications,
* permission explanations,
* AI explanations.

French must be used only where it is educationally relevant:

* French words,
* French sentences,
* examples,
* pronunciation,
* IPA,
* grammatical forms.

Internal code identifiers, classes, protocols, filenames, logs, comments, API field names, and developer documentation may be English.

Example:

GOOD UI:

tu devrais
/ty də.vʁɛ/

тебе стоит / тебе следовало бы

devoir → conditionnel présent

tu dois — ты должен
tu devrais — тебе стоит

[Прослушать] [Сохранить] [Подробнее]

BAD UI:

Save
Explain
Settings
History

Do not expose internal English feature names such as:
French Popup
Conversation Ghost
Command Palette

to the end user.

==================================================
TARGET PLATFORM
===============

Primary platform:

macOS

Target:

* modern macOS
* Apple Silicon
* native desktop experience

Use:

* Swift
* SwiftUI
* AppKit where SwiftUI is insufficient

Use AppKit where necessary for:

* NSPanel
* floating windows
* global overlays
* window positioning
* menu bar behavior
* keyboard shortcuts
* focus management

Do NOT build an iOS application yet.

Do NOT build Electron.

Do NOT build a web application pretending to be a Mac app.

==================================================
CHROME COMPANION
================

DéjàVu includes a small Chrome extension for selected-text functionality.

Use:

* Chrome Extension Manifest V3
* TypeScript preferred
* minimal dependencies
* content script
* extension service worker
* Shadow DOM for injected UI

The Chrome extension must NOT contain:

* AI API keys
* vocabulary database
* learning history
* primary application logic

It is only an integration layer.

==================================================
REPOSITORY STRUCTURE
====================

Create one repository.

Suggested structure:

dejavu/
macos/
DejavuApp/
chrome-extension/
shared/
schemas/
docs/
README.md

You may adjust this structure if Xcode conventions require it.

Keep the repository understandable.

Do not create unnecessary packages or microservices.

==================================================
DEVELOPMENT PHILOSOPHY
======================

CRITICAL:

Build incrementally.

Never attempt to implement the entire application in one step.

Complete exactly ONE development phase at a time.

After every phase:

1. compile the project,
2. run available tests,
3. fix compiler errors,
4. fix obvious runtime errors,
5. explain what was implemented,
6. list files created or modified,
7. explain how I can test the current phase manually,
8. STOP.

Do NOT start the next phase until I explicitly tell you to continue.

A small fully working implementation is much better than a large broken implementation.

Do not create fake placeholder architecture for future phases unless the abstraction is already useful.

Do not fill the repository with TODOs.

Debug-only mocks are allowed only when clearly marked and genuinely useful for development.

Never claim that something works unless it compiles or you have actually verified the available build/test process.

==================================================
TECHNICAL PRINCIPLES
====================

Prefer:

* native APIs,
* small architecture,
* explicit types,
* async/await,
* testable services,
* local-first storage,
* simple dependencies.

Avoid unnecessary:

* Firebase
* Supabase
* user authentication
* cloud databases
* Docker
* Redux-like state systems
* huge third-party UI frameworks
* analytics SDKs
* tracking
* unnecessary backend infrastructure

This is initially a personal local-first application.

==================================================
MACOS ARCHITECTURE
==================

Create modular application architecture.

Suggested services:

LanguageAnalysisService
VocabularyStore
HistoryStore
ClipboardMonitor
OverlayManager
ConversationGhostService
CommandPaletteController
LocalBridgeServer
SettingsStore
SpeechService
KeychainService
LanguageDetectionService
CacheService

Do not put all logic into SwiftUI views.

Separate:

* UI
* domain models
* application state
* persistence
* networking
* system integration
* AI integration

Use dependency injection where useful, but do not overengineer it.

==================================================
PERSISTENCE
===========

Prefer SwiftData unless there is a strong technical reason not to.

Store locally:

VocabularyEntry
AnalysisHistoryEntry
CommandPaletteHistoryEntry
ConversationHistoryEntry
AppSettings

Do not save unnecessary raw clipboard data.

==================================================
SHARED VOCABULARY
=================

Every feature must use ONE shared vocabulary store.

VocabularyEntry should support approximately:

id
french
normalizedForm
ipa
russianMeaning
lemma
partOfSpeech
exampleSentence
source
createdAt
lastSeenAt
seenCount
savedByUser
difficulty
notes

Possible source values:

chrome_popup
clipboard
command_palette
conversation_ghost

If the same expression is encountered again:

* do not create a duplicate,
* increment seenCount,
* update lastSeenAt,
* merge useful missing metadata where reasonable.

Normalize expressions carefully but never destroy meaningful French spelling.

==================================================
AI ARCHITECTURE
===============

Do not tightly couple the entire app to one AI vendor.

Create a protocol similar to:

LanguageModelProvider

Then implement a provider for OpenAI.

Use the current supported OpenAI API approach available in the chosen SDK/API at implementation time.

Keep provider and model configurable in settings.

Store the API key ONLY in macOS Keychain.

Never:

* hardcode the API key,
* save it in UserDefaults,
* commit it,
* expose it to Chrome,
* log it.

Create an AI connection test in settings.

==================================================
STRUCTURED AI RESPONSES
=======================

Prefer structured JSON output mapped into typed Swift models.

Core model:

FrenchAnalysis

Suggested fields:

original
translation
ipa
lemma
partOfSpeech
gender
article
verbForm
grammar
chunks
examples
difficulty
naturalnessNotes

Use separate optional structures rather than giant strings.

Example conceptual response:

{
"original": "leurs voitures",
"translation": "их машины",
"ipa": "/lœʁ vwa.tyʁ/",
"grammar": [
{
"title": "leurs",
"explanation": "Используется, потому что voitures стоит во множественном числе."
}
],
"examples": [
{
"fr": "Ils garent leurs voitures devant la maison.",
"translation": "Они паркуют свои машины перед домом."
}
],
"difficulty": "A2"
}

==================================================
FRENCH TEACHING STYLE
=====================

The learner is Russian-speaking.

Default level:
A2 → B1.

Explain in Russian.

Keep explanations practical.

Prefer patterns and contrasts.

GOOD:

leur voiture — одна вещь → leur

leurs voitures — несколько вещей → leurs

Количество владельцев здесь не определяет выбор.

BAD:

The possessive determiner displays morphosyntactic agreement with the possessed noun phrase.

Do not overwhelm the learner with linguistic terminology unless useful.

For a single noun, when useful show:

* gender,
* article,
* plural,
* IPA,
* translation.

For a conjugated verb show:

* infinitive,
* tense/mood,
* person,
* translation.

For a phrase show:

* translation,
* reusable structure,
* one or two examples.

For a sentence show:

* natural Russian translation,
* maximum 2–4 important learning points.

Do not turn every sentence into a full grammar lesson.

==================================================
IPA RULE
========

Use modern metropolitan French pronunciation.

For words such as "un", default to /ɛ̃/ rather than /œ̃/ unless specifically discussing dialectal or conservative pronunciation.

Do not attempt to invent IPA from spelling in Swift if a reliable result is unavailable.

==================================================
MAIN APPLICATION UI
===================

The main application should have approximately:

Главная
Сохранённое
История
Настройки

Do not create unnecessary navigation sections.

==================================================
HOME SCREEN
===========

Главная should feel useful, not like a fake analytics dashboard.

Possible content:

DéjàVu

Сегодня

Встречено выражений: X
Сохранено: X

Мини-диалоги
Активны / Приостановлены

Последнее

Recent expressions.

Do not invent meaningless XP, levels, coins, streak flames, trophies, or fake engagement mechanics.

==================================================
SAVED SCREEN
============

Сохранённое should allow:

* browsing saved expressions,
* search,
* opening an item,
* listening,
* viewing examples,
* viewing where it came from,
* removing from saved,
* adding personal notes.

Later this data can support spaced repetition, but do not build a full SRS unless explicitly requested.

==================================================
HISTORY SCREEN
==============

History should combine useful analyses from:

* selected text,
* clipboard,
* command palette,
* mini-dialogues.

Show source subtly.

Allow search.

Avoid storing irrelevant clipboard content.

==================================================
MENU BAR
========

DéjàVu must also work from the macOS menu bar.

Menu approximately:

Открыть DéjàVu

Быстрый помощник

Разбор скопированного
✓ Включён / Выключен

Мини-диалоги
✓ Включены / Выключены

Сохранённое

Настройки

Выход

==================================================
DESIGN LANGUAGE
===============

Design direction:

* premium native macOS utility,
* calm,
* restrained,
* modern,
* excellent typography,
* generous spacing,
* subtle materials,
* rounded corners,
* native light/dark mode,
* subtle shadows,
* tasteful animation.

Reference feeling:

Raycast
Arc
Spotlight
modern Apple utilities

Avoid:

* Duolingo imitation,
* childish illustrations,
* cartoon mascots,
* giant gradients,
* excessive emoji,
* gamification,
* overly colorful dashboards,
* huge cards everywhere.

The application should feel at home on macOS.

==================================================
FEATURE 1 — БЫСТРЫЙ ПОМОЩНИК
Internal: Command Palette
=========================

This should be the first major user-facing feature.

Default global shortcut:

Command + Shift + F

The shortcut should be configurable later.

Pressing it anywhere on macOS opens a floating Spotlight-like panel.

Pressing Escape closes it.

Opening the panel must NOT depend on AI/network access.

The UI should appear instantly.

Approximate width:
600–650 px

Use a borderless floating NSPanel if appropriate.

The text field should focus immediately.

Russian placeholder:

Спросите что-нибудь о французском…

Accept natural questions such as:

leur vs leurs

tu devrais

как сказать both

IPA rendez le véhicule

проспрягай rendre

почему à la fin de la location

en route здесь нормально?

trajet vs voyage vs route

исправь: je suis passé une agence

No strict command syntax should be required.

Optional advanced slash commands may exist later:

/перевод
/ipa
/грамматика
/спряжение
/примеры
/исправь

But natural input is primary.

Results must be compact.

Example:

tu devrais
/ty də.vʁɛ/

тебе стоит / тебе следовало бы

devoir
conditionnel présent

Сравните:

tu dois — ты должен
tu devrais — тебе стоит

Пример:
Tu devrais appeler demain.

[Прослушать] [Сохранить] [Подробнее]

Keyboard support:

Enter → отправить
Escape → закрыть
Command+S → сохранить
Command+L → прослушать
Command+K → очистить
Up/Down → история запросов

Search local cached analyses before making duplicate AI requests.

Support one lightweight follow-up question after an answer.

Do NOT build a full ChatGPT clone.

==================================================
FEATURE 2 — РАЗБОР СКОПИРОВАННОГО
Internal: French Clipboard
==========================

Use NSPasteboard.general.

Monitor pasteboard changes intelligently.

Prefer changeCount rather than blindly rereading forever.

Clipboard monitoring must be OFF until the user explicitly enables it.

Settings:

Разбор скопированного

[ ] Включить

[ ] Автоматически разбирать французский текст

[ ] Показывать всплывающее окно

[ ] Сохранять историю разборов

Use Apple's NaturalLanguage framework or equivalent native local language detection where appropriate.

Workflow:

1. clipboard changes,
2. get textual content,
3. reject empty,
4. reject unreasonable length,
5. reject duplicates,
6. detect likely language locally,
7. only if likely French, continue,
8. analyse,
9. show compact floating result.

Never automatically upload clearly non-French clipboard text.

For long text, do not auto-submit.

Example:

Скопирован французский текст

842 символа

[Разобрать] [Игнорировать]

Suggested auto-analysis max:
approximately 500 characters.

Result should appear in a subtle floating panel.

Example:

DéjàVu

tu devrais
/ty də.vʁɛ/

тебе стоит / тебе следовало бы

devoir → conditionnel présent

tu dois — ты должен
tu devrais — тебе стоит

[Прослушать] [Сохранить] [Подробнее]

Behavior:

* floats above normal windows,
* does not aggressively steal focus,
* auto-dismisses,
* pauses dismissal on hover,
* can be manually closed,
* new results replace the old panel instead of endlessly stacking.

Suppress duplicate repeated clipboard events.

==================================================
FEATURE 3 — РАЗБОР ВЫДЕЛЕННОГО
Internal: French Popup
======================

Implemented through Chrome companion extension.

When the user selects likely French text on a normal webpage, show a tiny unobtrusive DéjàVu bubble near the selection.

Do NOT instantly call AI whenever selection changes.

Flow:

select French text
→ tiny action bubble appears
→ user clicks bubble
→ analysis request happens
→ full popup opens

Use:

Range.getBoundingClientRect()

or equivalent for positioning.

Keep the popup inside the viewport.

Use Shadow DOM.

The host webpage's CSS must not break DéjàVu.

DéjàVu CSS must not leak into the webpage.

Do not render AI content through unsafe innerHTML.

Use safe text rendering.

For a word show:

garent
/ɡaʁ/

garer
глагол

ils garent
présent · 3-е лицо мн. числа

паркуют / ставят машину

Пример:

Ils garent leur voiture devant la gare.
Они паркуют машину перед вокзалом.

[Прослушать]
[Сохранить]
[Подробнее]

For phrases:

à la fin de la location
/a la fɛ̃ də la lɔ.ka.sjɔ̃/

в конце срока аренды

Полезная конструкция:

à la fin de + существительное

à la fin du mois
à la fin du film
à la fin de l'année

For a full sentence:

* translation,
* a few important grammar/chunk insights,
* useful vocabulary,
* not an essay.

When sending AI context, send only:

selectedText
sentenceContainingSelection when available
small nearby context when necessary
pageLanguage
pageTitle
source

Never send the entire webpage.

Ignore:

URLs
code
random numbers
empty selection
obviously irrelevant data

But very short French expressions must still work:

du tout
leurs
en route
tu devrais

==================================================
CHROME ↔ MAC CONNECTION
=======================

For MVP, implement a simple local bridge.

macOS app runs local HTTP server bound ONLY to:

127.0.0.1

Never:

0.0.0.0

Never expose it to LAN.

Suggested endpoints:

GET /v1/health
POST /v1/analyze
POST /v1/save
POST /v1/explain
POST /v1/listen

Use a local pairing token.

Generate it securely.

Store it securely in macOS.

Chrome may store ONLY the local pairing token.

Chrome must never receive the AI provider key.

Create simple pairing experience:

Настройки
→ Расширение Chrome
→ Подключить расширение

Architect the bridge so it could later be replaced by Chrome Native Messaging without rewriting all application logic.

==================================================
CHROME TOOLBAR POPUP
====================

The browser extension toolbar popup should stay minimal.

Russian UI:

DéjàVu

Приложение подключено ✓

Разбор выделенного
[Вкл / Выкл]

[Подключить к Mac]

[Открыть DéjàVu]

Allow:

* enabling/disabling selection popup,
* domain blacklist,
* pairing.

Do not recreate the entire app inside the extension popup.

==================================================
FEATURE 4 — МИНИ-ДИАЛОГИ
Internal: Conversation Ghost
============================

This is not a normal lesson.

DéjàVu occasionally appears with one short realistic French question.

Example:

DéjàVu

Tu fais quoi ce soir ?

[Ответить голосом]
[Написать]

User:

Je vais rester chez moi parce que je suis fatigué.

Feedback:

✓ Хорошо

Естественнее:

Je pense rester chez moi ce soir parce que je suis fatigué.

Полезно:

penser + infinitif
→ планировать / собираться

[Сохранить фразу]
[Готово]

Do NOT show:

* points,
* percentages,
* grades,
* XP,
* streaks.

Use a compact floating NSPanel.

Default location:
bottom-right.

Respect:

* Dock,
* safe screen bounds,
* multiple displays.

Settings:

Мини-диалоги
[Вкл / Выкл]

Частота:
20 минут
30 минут
45 минут
60 минут
Другая

Default:
45 minutes

But do not behave like a dumb exact timer.

Only show when reasonably appropriate:

* Mac is actively being used,
* screen is unlocked,
* no existing dialogue is open.

Where reasonably detectable, avoid:

* full-screen video,
* presentations,
* screen sharing,
* obvious interruptions.

Include:

Отложить на час
Приостановить до завтра

==================================================
MINI-DIALOGUE CONTEXTS
======================

Rotate realistic contexts:

friend
coworker
café
shop
train station
airport
hotel
landlord
doctor reception
neighbour
French administration
small talk
making plans
asking for help
giving an opinion

Questions must sound natural.

GOOD:

Tu fais quoi ce week-end ?

Vous avez rendez-vous ?

Vous cherchez quelque chose ?

Tu veux qu'on mange où ?

Vous avez déjà rempli ce formulaire ?

BAD:

Décrivez votre passe-temps préféré en cinq phrases.

Difficulty:
A2 by default.

Occasionally stretch toward B1.

==================================================
VOICE INPUT
===========

Mini-dialogues support:

1. voice response,
2. typed response.

For voice:

* request microphone permission properly,
* use appropriate native Apple speech recognition when practical,
* recognition language = fr-FR,
* show transcription,
* never activate microphone automatically.

Recording starts ONLY after explicit user action.

==================================================
DIALOGUE FEEDBACK
=================

AI feedback should be structured approximately as:

{
"understood": true,
"correctedVersion": "...",
"moreNaturalVersion": "...",
"mainIssue": "...",
"usefulPhrase": "...",
"encouragement": "..."
}

Correction priorities:

1. meaning-changing errors,
2. common grammar errors,
3. unnatural phrasing,
4. one useful improvement.

Maximum one or two learning points.

If the user's answer is already natural:

do not invent errors.

Show:

✓ Звучит естественно

No correction required.

==================================================
PERSONALIZATION
===============

Over time, DéjàVu should use its local learning data.

Mini-dialogues may reuse:

* recently saved expressions,
* frequently encountered phrases,
* difficult structures.

Do not force saved vocabulary into unnatural sentences.

Track recently used dialogue contexts and questions to prevent repetitive prompts.

==================================================
SPEECH / LISTEN
===============

French words and examples should support:

Прослушать

Prefer:

fr-FR

Use native speech synthesis where it produces acceptable pronunciation.

Abstract speech through SpeechService so implementation can change later.

==================================================
PRIVACY
========

Privacy is critical because clipboard and selected text may contain sensitive information.

Rules:

* clipboard monitoring is opt-in,
* never intentionally capture secure/password fields,
* locally detect language before sending clipboard data when possible,
* never persist arbitrary clipboard contents,
* only persist successful French analysis/history when appropriate,
* allow disabling Clipboard instantly,
* show what type of data may be sent to AI,
* API keys remain in Keychain,
* browser bridge binds only to localhost,
* Chrome never receives the AI secret.

Create Settings → Конфиденциальность.

Explain permissions in clear Russian language.

Do not use manipulative language.

==================================================
SETTINGS
========

Create a clean settings window.

Suggested sections:

Общие

AI

Быстрый помощник

Разбор скопированного

Расширение Chrome

Мини-диалоги

Голос

Конфиденциальность

О приложении

==================================================
ONBOARDING
==========

First launch onboarding should be short.

Suggested steps:

1. Добро пожаловать в DéjàVu

Short explanation.

2. Подключение AI

Enter API key.

Store in Keychain.

Button:

Проверить подключение

3. Быстрый помощник

Explain global shortcut.

4. Разбор скопированного

Optional.

Explain clipboard permission.

5. Расширение Chrome

Optional.

6. Мини-диалоги

Optional.

7. Готово

Do not force optional features.

The user should always be able to enter the app and configure later.

==================================================
ERROR HANDLING
==============

All user-facing errors are Russian.

Examples:

Не удалось подключиться к AI.

[Повторить]

API-ключ не настроен.

[Открыть настройки]

DéjàVu не запущен.

[Открыть приложение]

Нет соединения с интернетом.

Do not crash on recoverable failures.

Do not spam alerts.

Use subtle inline error states where possible.

==================================================
LOADING STATES
==============

Avoid giant spinners.

Use:

* subtle progress indicators,
* skeletons,
* lightweight animated states.

The UI should remain responsive.

==================================================
CACHE
=====

Avoid unnecessary duplicate AI calls.

Cache recent identical analyses.

If:

tu devrais

was recently analysed, reuse it.

Allow user to explicitly request a fresh answer when appropriate.

Do not cache forever without limits.

==================================================
LOGGING
========

Use useful development logging.

Never log:

* API keys,
* pairing tokens,
* full sensitive clipboard contents.

Keep production logging conservative.

==================================================
ACCESSIBILITY
=============

Where reasonable:

* keyboard navigation,
* VoiceOver labels,
* sufficient contrast,
* dynamic system appearance,
* logical focus behavior.

Command Palette must be fully keyboard-usable.

==================================================
TESTING EXPECTATIONS
====================

Add focused tests for important non-UI logic:

* vocabulary deduplication,
* normalization,
* cache,
* language filtering,
* settings persistence,
* safe bridge authentication.

Do not chase 100% coverage.

Test meaningful behavior.

==================================================
BUILD PHASES
============

Follow this EXACT phase order.

---

## PHASE 1 — FOUNDATION

Create:

* repository structure,
* Xcode/macOS project,
* app shell,
* basic navigation,
* menu bar foundation,
* domain models,
* SwiftData persistence,
* VocabularyStore,
* HistoryStore,
* SettingsStore,
* KeychainService,
* LanguageModelProvider protocol,
* OpenAI provider,
* FrenchAnalysis models,
* AI connection test,
* basic manual analysis screen for development.

All visible UI must already be Russian.

Compile and stop.

---

## PHASE 2 — БЫСТРЫЙ ПОМОЩНИК

Implement:

* global shortcut,
* NSPanel,
* input,
* natural French questions,
* AI analysis,
* local cache,
* query history,
* Listen,
* Save,
* More,
* keyboard controls,
* one follow-up question,
* Russian UI.

Compile, test, stop.

---

## PHASE 3 — РАЗБОР СКОПИРОВАННОГО

Implement:

* NSPasteboard monitoring,
* local language detection,
* duplicate suppression,
* privacy settings,
* floating result panel,
* save,
* listen,
* history,
* enable/disable from menu bar.

Compile, test, stop.

---

## PHASE 4 — LOCAL BROWSER BRIDGE

Implement:

* localhost-only HTTP server,
* secure random pairing token,
* authentication,
* health endpoint,
* analysis endpoint,
* save endpoint,
* proper errors,
* browser integration settings UI.

Compile, test, stop.

---

## PHASE 5 — CHROME EXTENSION

Create:

* Manifest V3 extension,
* selection detection,
* action bubble,
* Shadow DOM popup,
* connection to Mac,
* Save,
* Listen,
* More,
* domain blacklist,
* extension toolbar popup,
* pairing.

Test on several webpages.

Stop.

---

## PHASE 6 — МИНИ-ДИАЛОГИ

Implement:

* scheduler,
* intelligent trigger conditions,
* floating NSPanel,
* generated scenarios,
* voice response,
* typed response,
* correction,
* more natural version,
* save useful phrases,
* context rotation,
* reuse of saved vocabulary,
* snooze,
* pause until tomorrow.

Include:

Trigger Ghost Now

as a Debug/development action, but label it appropriately in Russian if exposed.

Compile, test, stop.

---

## PHASE 7 — PRODUCT POLISH

Only after all previous phases work:

* onboarding,
* permissions polish,
* accessibility,
* empty states,
* animations,
* UI consistency,
* dark mode review,
* error handling,
* caching review,
* privacy review,
* README,
* clean build,
* remove dead code,
* remove temporary debug UI not needed.

Do not introduce major new features.

==================================================
PHASE COMPLETION FORMAT
=======================

At the end of EVERY phase respond with:

## Что готово

Concise description.

## Изменённые файлы

Exact file list.

## Как проверить

Exact numbered manual test procedure.

## Что ещё не реализовано

Only features belonging to later phases.

## Статус сборки

Clearly state whether the project successfully compiled and what command/build process was used.

Then STOP.

Do not continue to the next phase.

==================================================
IMPORTANT ANTI-VIBE-CODING FAILURE RULES
========================================

Never:

* generate 50 placeholder files without implementation,
* pretend a feature works without compilation,
* silently replace native functionality with a fake mock,
* hardcode fake AI responses in production,
* put API keys in source,
* add unnecessary backend infrastructure,
* add authentication,
* build iOS before macOS works,
* create four separate databases,
* create four unrelated AI systems,
* duplicate FrenchAnalysis models per feature,
* rebuild working architecture from scratch during each phase,
* redesign completed features unnecessarily,
* delete working code merely because you prefer another pattern,
* continue through compiler errors,
* begin multiple phases at once.

Before changing existing architecture, first inspect what already exists.

Prefer extending working code.

==================================================
SUCCESS CRITERIA
================

The finished product should make this workflow possible:

I see:

tu devrais

on a website.

I select it.

DéjàVu explains it.

I save it.

Later I copy:

Vous devriez remplir ce formulaire.

DéjàVu recognizes it and explains the relationship.

Later a mini-dialogue asks:

Vous avez déjà rempli ce formulaire ?

I answer in French.

DéjàVu corrects me briefly.

Later I forget the difference between:

dois
devrais

I press:

Command + Shift + F

and type:

dois vs devrais

I get an immediate useful answer.

Everything feels like one connected product.

==================================================
START NOW
=========

Begin with PHASE 1 ONLY.

First inspect the empty workspace.

Then create the repository and working macOS foundation.

Do not begin Phase 2.

Do not ask me broad planning questions.

Make reasonable implementation decisions yourself.

Compile everything you create.

Fix all errors you encounter.

Stop after Phase 1 and provide the required phase completion report.
