# Фаза 4 — локальный мост браузера

## Что готово

HTTP-сервер на 127.0.0.1:17389, отдельный случайный код подключения в Keychain, авторизация, строгая проверка Host/Origin, CORS для одного настроенного расширения, /v1/health, /v1/analyze, /v1/save, русские ошибки и настройки подключения. Версия 0.4.0.

Новый мост выключен по умолчанию. Ключ OpenAI никогда не передаётся клиенту; запросы разбора используют общий сервис приложения. Сохранение принимает только ID ранее выданного разбора. Смена кода отзывает прежний доступ и закрывает соединения.

## Как проверить

1. Запустите приложение или Xcode-проект. Откройте «Настройки» → «Расширение Chrome». На первом запуске подключение выключено.
2. При готовом локальном клиенте нажмите «Подключить расширение». Статус должен стать «Готово к подключению». Если порт занят, появится понятная ошибка; после устранения конфликта нажмите повторное подключение.
3. Покажите код подключения и передайте его только доверенному локальному клиенту/расширению. Для браузерного клиента предварительно задайте точный ID расширения. Не публикуйте код, не передавайте в URL и не записывайте в shell history.
4. Вызовите GET /v1/health с авторизацией: 200. Без авторизации: 401. Host другого домена или Origin обычной страницы: 403.
5. POST /v1/analyze с JSON `{"text":"tu devrais"}` возвращает ID и разбор. POST /v1/save с этим ID сохраняет выражение; повтор не создаёт дубликат. Неверный ID возвращает 404.
6. «Заменить код подключения» отзывает старый код и старые ID разбора. «Отключить» закрывает сервер. При выключенной общей истории разбор не записывается автоматически, явное сохранение доступно.

Полный контракт: [BRIDGE_API.md](BRIDGE_API.md). Само расширение и проверки его разрешений относятся к фазе 5.

## Результаты проверки

- 52 теста прошли, 0 ошибок, 0 пропусков, включая регрессию фаз 1–3.
- HTTP-парсер проверен на неполных сообщениях, дублирующихся заголовках, chunking, отрицательной/чрезмерной длине, лишних байтах, абсолютном URL и передаче кода в query string.
- Проверены обязательная авторизация, неправильный Host, обычные веб-страницы и чужие расширения, разрешённый preflight, корректные HTTP-ошибки и отсутствие кода в ответе health.
- Через настоящий NWListener и URLSession на отдельном loopback-порту проверены 401 без кода, авторизованный health, analyze, save, no-store и прекращение соединений после stop. Провайдер ИИ в тестах фиктивный; пользовательские данные и реальный ключ не используются.
- Проверены общий словарь/идемпотентное сохранение, неизвестные/инвалидированные ID, отсутствие сырого вопроса в таблице команд, отключение и очистка во время запроса, изменения истории и лимит 20 анализов в минуту.
- Генерация/повторное получение/замена случайного кода проверены с тестовым хранилищем. Отдельно проверена изоляция аккаунтов в настоящей Keychain на временном тестовом service; записи удаляются по завершении.
- Чистая Release-сборка успешна. После правки текста настроек выполнена повторная Release-сборка. Подпись проверена `codesign --verify --deep --strict`.
- Release 0.4.0 запущена, существующие данные и настройки доступны, новый мост выключен; раздел подключения проверен визуально. Рабочий пользовательский код подключения не показывался и не копировался.
- Реальный Chrome-клиент, браузерные разрешения Local Network Access, доступ с отдельного LAN-устройства, macOS 14 на отдельном компьютере и конфликт занятого порта вручную ещё не проверялись. Привязка к 127.0.0.1 задана явно в Network.framework, wildcard и публикация сервиса отсутствуют.
- Среда: Apple Silicon, macOS 26.0.1, Xcode 26.2. Диагностическое предупреждение DVTDeviceOperation не мешает сборке или тестам.

## Статус сборки

```sh
xcodebuild -quiet -project macos/DejavuApp.xcodeproj -scheme DejavuApp -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dejavu-derived test
xcodebuild -quiet -project macos/DejavuApp.xcodeproj -scheme DejavuApp -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build clean build
codesign --verify --deep --strict build/Build/Products/Release/DejavuApp.app
```

Локальная ad-hoc сборка: `build/Build/Products/Release/DejavuApp.app`. Developer ID/notarization не настраивались. Сборки, ключи, базы и результаты тестов не входят в репозиторий.

## Что ещё не реализовано

Фазы 5–7: Chrome-расширение, мини-диалоги, финальная полировка. /v1/explain и /v1/listen — предложенные в общем задании дополнительные маршруты; в фазе 4 реализованы обязательные health/analyze/save.

## Изменённые файлы

- `AGENTS.md`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/BRIDGE_API.md`
- `docs/PHASE_4.md`
- `macos/DejavuApp.xcodeproj/project.pbxproj`
- `macos/DejavuApp/App/AppEnvironment.swift`
- `macos/DejavuApp/Bridge/BridgeHTTP.swift`
- `macos/DejavuApp/Bridge/BridgeRouter.swift`
- `macos/DejavuApp/Bridge/BrowserBridge.swift`
- `macos/DejavuApp/Bridge/LocalHTTPServer.swift`
- `macos/DejavuApp/Domain/AppError.swift`
- `macos/DejavuApp/Persistence/Models.swift`
- `macos/DejavuApp/Persistence/SettingsStore.swift`
- `macos/DejavuApp/Resources/DejavuApp.entitlements`
- `macos/DejavuApp/Resources/Info.plist`
- `macos/DejavuApp/Services/KeychainService.swift`
- `macos/DejavuApp/Views/BrowserBridgeSettings.swift`
- `macos/DejavuApp/Views/SettingsView.swift`
- `macos/DejavuAppTests/BridgeTests.swift`
