# Фаза 2 — быстрый помощник

## Что готово

Нативная NSPanel, регистрация ⌘⇧F, свободный вопрос на русском или французском, реальный ИИ-разбор, компактный ответ и подробности, сохранение в общий словарь, французское системное озвучивание, одно уточнение, история запросов и общий кэш. Клавиши Enter, Esc, ⌘S, ⌘L, ⌘K, ↑↓. Все новые элементы интерфейса — на русском.

История ограничена 100 успешными вопросами, управляется общей настройкой приватности. Кэш ограничен 100 ответами и 30 минутами, находится только в памяти. Закрытие панели отменяет запрос; поздний ответ не сохраняется. Новая таблица добавляется к существующей базе без её удаления.

## Как проверить

1. Запустить приложение, при необходимости настроить ключ в настройках.
2. В другом приложении нажать ⌘⇧F. Проверить появление панели и фокус ввода. При конфликте сочетания открыть настройки, освободить сочетание и повторить регистрацию. Запуск из меню и главного окна доступен независимо от регистрации.
3. Ввести `tu devrais`, Enter. Проверить перевод и объяснение. ⌘S сохраняет, ⌘L произносит, «Подробнее» раскрывает ответ.
4. Повторить Enter: появляется отметка «Недавний ответ · без нового запроса». «Обновить ответ» выполняет новый запрос.
5. Нажать «Задать уточнение», ввести `Чем это мягче, чем tu dois?`. Должно появиться сравнение форм. Затем «Новый вопрос» или ⌘K.
6. Ввести черновик, нажать ↑, затем ↓: черновик восстанавливается. Esc закрывает панель. Проверить повторное открытие.
7. При отключённой истории новый ответ не записывается автоматически; явное сохранение продолжает работать.

## Результаты проверки

- Debug: 28 тестов, 0 ошибок. Проверены запрос уточнения, TTL/LRU и ключ кэша, смена модели, принудительное обновление, отмена, история, отключение/включение истории в полёте, сохранение, вызов озвучивания, фильтрация строкового null, расположение панели, миграция базы фазы 1.
- Чистая Release-сборка успешна, локальная подпись проверена `codesign --verify --deep --strict`.
- Живая проверка: реальный ответ через настроенное подключение, уточнение с сравнением, повтор из кэша, сохранение по ⌘S, запуск озвучивания по ⌘L, подробности, ⌘K, ↑↓ с восстановлением черновика, Esc. Release открылась с существующей базой.
- Глобальная регистрация не показывает ошибки, но вызов из другого приложения не подтверждён: синтетическое сочетание UI-автоматизации не открыло панель. Нужна проверка физической клавиатурой по пункту 2. Это ограничение проверки, а не подтверждённый успешный сценарий.
- Проверено на Apple Silicon, macOS 26.0.1 / Xcode 26.2. На отдельном Mac с macOS 14 и физическом втором дисплее не проверялось; расчёт границ второго экрана покрыт тестами.
- Ответы ИИ вероятностные. После живой проверки уточнены инструкции для сравнения форм и необязательных метаданных; компактный ответ показывает до двух грамматических пунктов.
- Сборка локальная, без Developer ID/notarization. Xcode печатает предупреждение DVTDeviceOperation о пустом build number устройства; сборка и тесты завершаются успешно.

Команды из корня:

```sh
xcodebuild -quiet -project macos/DejavuApp.xcodeproj -scheme DejavuApp -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dejavu-derived test
xcodebuild -quiet -project macos/DejavuApp.xcodeproj -scheme DejavuApp -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build clean build
codesign --verify --deep --strict build/Build/Products/Release/DejavuApp.app
```

Результат: `build/Build/Products/Release/DejavuApp.app`. Тестовые результаты и данные приложения не входят в репозиторий. Ключ остаётся в Keychain; секреты не используются в коде и примерах.

## Что ещё не реализовано

Фазы 3–7: разбор буфера обмена, локальный мост, Chrome, мини-диалоги и финальная полировка. Они не начинались.

## Изменённые файлы

- `AGENTS.md`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/PHASE_2.md`
- `macos/DejavuApp.xcodeproj/project.pbxproj`
- `macos/DejavuApp/App/AppEnvironment.swift`
- `macos/DejavuApp/App/DejavuApp.swift`
- `macos/DejavuApp/Domain/AnalysisRequest.swift`
- `macos/DejavuApp/Domain/AppError.swift`
- `macos/DejavuApp/Domain/FrenchAnalysis.swift`
- `macos/DejavuApp/Persistence/CommandPaletteHistoryStore.swift`
- `macos/DejavuApp/Persistence/HistoryStore.swift`
- `macos/DejavuApp/Persistence/Models.swift`
- `macos/DejavuApp/Persistence/PersistenceController.swift`
- `macos/DejavuApp/Persistence/SettingsStore.swift`
- `macos/DejavuApp/Resources/Info.plist`
- `macos/DejavuApp/Services/AnalysisCache.swift`
- `macos/DejavuApp/Services/LanguageAnalysisService.swift`
- `macos/DejavuApp/Services/LanguageModelProvider.swift`
- `macos/DejavuApp/Services/OpenAIProvider.swift`
- `macos/DejavuApp/Services/SpeechService.swift`
- `macos/DejavuApp/System/CommandPaletteController.swift`
- `macos/DejavuApp/System/GlobalShortcut.swift`
- `macos/DejavuApp/Views/AnalysisView.swift`
- `macos/DejavuApp/Views/CommandPaletteModel.swift`
- `macos/DejavuApp/Views/CommandPaletteView.swift`
- `macos/DejavuApp/Views/HomeView.swift`
- `macos/DejavuApp/Views/ManualAnalysisModel.swift`
- `macos/DejavuApp/Views/PaletteInput.swift`
- `macos/DejavuApp/Views/RootView.swift`
- `macos/DejavuApp/Views/SettingsView.swift`
- `macos/DejavuAppTests/CommandPaletteTests.swift`
- `macos/DejavuAppTests/OpenAIProviderTests.swift`
