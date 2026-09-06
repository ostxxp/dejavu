# Фаза 1 — проверка

Дата: 2026-09-06. Только фаза 1; фаза 2 не начата.

## Результат

Нативное приложение на Swift 6, SwiftUI/AppKit и SwiftData. Главная с ручным разбором, сохранённые выражения с поиском и заметками, общая история, русские настройки, отдельное окно настроек и MenuBarExtra. Ключ — в Keychain. Реальный провайдер OpenAI использует Responses API и общую строгую схему, без production-моков.

## Автоматические проверки

- Debug build: успешно, arm64 и x86_64.
- XCTest: **14 пройдено, 0 ошибок, 0 пропущено**, на Apple Silicon, macOS 26.0.1, Xcode 26.2.
- Чистый Release build: успешно, arm64 и x86_64; без сторонних зависимостей.
- Нормализация и дедупликация, объединение метаданных, идемпотентное сохранение, история и её очистка.
- Повторное открытие временной базы с диска и сохранение настроек.
- Запись, чтение, замена, валидация и удаление фиктивного значения в отдельной записи Keychain.
- Формат запроса, `store: false`, строгая схема, разбор ответа, отказ, неполный JSON, ошибки HTTP, тайм-аут и отмена.
- Пустой/слишком длинный ввод отклоняется до транспорта; отсутствие ключа не запускает сеть.

Команды из корня проекта:

```sh
xcodebuild -project macos/DejavuApp.xcodeproj -scheme DejavuApp \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/dejavu-derived build

xcodebuild -quiet -project macos/DejavuApp.xcodeproj -scheme DejavuApp \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/dejavu-derived \
  -resultBundlePath /tmp/dejavu-phase1-verified.xcresult test

xcodebuild -quiet -project macos/DejavuApp.xcodeproj -scheme DejavuApp \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build clean build
```

При повторном запуске с `-resultBundlePath` выберите новый путь или опустите этот параметр. Итоговая локальная Release-сборка: `build/Build/Products/Release/DejavuApp.app`. Сборки и отчёты исключены из Git.

## Проверено в интерфейсе

- Приложение запускается; «Главная» открывается с нулевыми счётчиками, без фиктивных данных.
- Ввод `tu devrais` и «Разобрать» без ключа показывают русское сообщение с переходом к настройкам.
- Пустые «Сохранённое» и «История», поиск и русские системные меню отображаются корректно.
- Настройки открываются из бокового меню и отдельным окном по ⌘,.

Реальный запрос к OpenAI не выполнялся: пользовательский API-ключ не предоставлен. Сетевой контракт и ошибки проверены изолированным транспортом в тестах. Качество живых ответов и доступность выбранной модели предстоит проверить со своим ключом.

## Ручная проверка

1. Откройте `macos/DejavuApp.xcodeproj`, выберите `DejavuApp` → «Мой Mac» и нажмите ⌘R. Либо запустите готовую локальную Release-сборку.
2. Перейдите в «Настройки». Сохраните ключ OpenAI только через защищённое поле приложения.
3. Оставьте `gpt-4o-mini` или сохраните другую модель с поддержкой структурированного вывода. Нажмите «Проверить подключение»; ожидается «Подключение работает. Разбор получен.».
4. На «Главной» разберите `tu devrais`: ожидаются русский перевод и пояснения, французские примеры и транскрипция при наличии.
5. Нажмите «Сохранить», откройте «Сохранённое», найдите выражение, добавьте заметку. Повторный разбор того же выражения не должен создавать вторую словарную запись.
6. Перезапустите приложение: выражение, заметка и история должны остаться.
7. Выключите историю в настройках и разберите другое выражение. Оно не должно появиться в истории или сохранённом без явного нажатия «Сохранить».
8. Закройте главное окно. В строке меню macOS откройте меню DéjàVu и выберите «Открыть DéjàVu» или «Сохранённое».
9. Для проверки сетевой ошибки временно укажите недоступную модель и сохраните настройки; после проверки верните рабочую модель.

## Последующие фазы

2. Быстрый помощник: глобальная клавиша, NSPanel, кэш, озвучивание и уточнение.
3. Разбор скопированного: согласие пользователя, локальная фильтрация и панель.
4. Защищённый локальный мост.
5. Расширение Chrome.
6. Мини-диалоги и голосовой ввод.
7. Онбординг и финальная полировка.

## Точный список изменённых файлов

- `.gitignore`
- `AGENTS.md`
- `README.md`
- `chrome-extension/README.md`
- `docs/ARCHITECTURE.md`
- `docs/PHASE_1.md`
- `docs/PRODUCT_SPEC.md`
- `macos/DejavuApp.xcodeproj/project.pbxproj`
- `macos/DejavuApp.xcodeproj/xcshareddata/xcschemes/DejavuApp.xcscheme`
- `macos/DejavuApp/App/AppEnvironment.swift`
- `macos/DejavuApp/App/DejavuApp.swift`
- `macos/DejavuApp/Domain/AppError.swift`
- `macos/DejavuApp/Domain/FrenchAnalysis.swift`
- `macos/DejavuApp/Persistence/HistoryStore.swift`
- `macos/DejavuApp/Persistence/Models.swift`
- `macos/DejavuApp/Persistence/PersistenceController.swift`
- `macos/DejavuApp/Persistence/SettingsStore.swift`
- `macos/DejavuApp/Persistence/VocabularyStore.swift`
- `macos/DejavuApp/Resources/DejavuApp.entitlements`
- `macos/DejavuApp/Resources/Info.plist`
- `macos/DejavuApp/Services/KeychainService.swift`
- `macos/DejavuApp/Services/LanguageAnalysisService.swift`
- `macos/DejavuApp/Services/LanguageModelProvider.swift`
- `macos/DejavuApp/Services/OpenAIProvider.swift`
- `macos/DejavuApp/Views/AnalysisView.swift`
- `macos/DejavuApp/Views/HomeView.swift`
- `macos/DejavuApp/Views/LibraryViews.swift`
- `macos/DejavuApp/Views/ManualAnalysisModel.swift`
- `macos/DejavuApp/Views/RootView.swift`
- `macos/DejavuApp/Views/SettingsView.swift`
- `macos/DejavuAppTests/OpenAIProviderTests.swift`
- `macos/DejavuAppTests/PersistenceTests.swift`
- `shared/schemas/french-analysis.json`
