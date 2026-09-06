import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var provider: AIProvider = .openAI
    @State private var model = ""
    @State private var saveHistory = true
    @State private var newKey = ""
    @State private var keyIsStored = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var testing = false
    @State private var connectionTask: Task<Void, Never>?
    @State private var clearConfirmation = false

    var body: some View {
        Form {
            Section("Подключение ИИ") {
                Picker("Поставщик", selection: $provider) {
                    ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
                }
                TextField("Модель", text: $model)
                    .autocorrectionDisabled()
                Text("Модель должна поддерживать структурированный разбор. По умолчанию — gpt-4o-mini.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Сохранить настройки") { saveSettings() }
                    .disabled(testing)
            }
            Section("Ключ доступа") {
                Label(keyIsStored ? "Ключ сохранён в Связке ключей" : "Ключ пока не добавлен",
                      systemImage: keyIsStored ? "lock.shield" : "key")
                SecureField("Введите новый ключ", text: $newKey)
                    .autocorrectionDisabled()
                    .privacySensitive()
                HStack {
                    Button("Сохранить ключ") {
                        perform {
                            try app.keychain.save(newKey)
                            app.analysisService.clearCache()
                            newKey = ""
                            keyIsStored = true
                            notice = "Ключ сохранён в Связке ключей"
                        }
                    }.disabled(newKey.isEmpty || testing)
                    Button("Удалить ключ", role: .destructive) {
                        perform {
                            try app.keychain.delete()
                            app.analysisService.clearCache()
                            newKey = ""
                            keyIsStored = false
                            notice = "Ключ удалён"
                        }
                    }.disabled(!keyIsStored || testing)
                }
                HStack {
                    Button("Проверить подключение") { testConnection() }
                        .disabled(testing || !keyIsStored)
                    if testing {
                        ProgressView().controlSize(.small)
                        Button("Отменить") { connectionTask?.cancel() }
                    }
                }
                Text("Проверка отправит слово «bonjour» в сохранённую модель. Это небольшой платный запрос; в историю он не попадёт.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Быстрый помощник") {
                LabeledContent("Горячая клавиша", value: "⌘⇧F")
                Button("Открыть помощник") { app.commandPalette.show() }
                Text("Enter — отправить · Esc — закрыть · ⌘S — сохранить · ⌘L — прослушать · ⌘K — очистить · ↑↓ — история запросов.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = app.commandPalette.shortcut.registrationError {
                    Text(error).foregroundStyle(.red)
                    Button("Повторить регистрацию клавиши") { app.commandPalette.retryShortcut() }
                }
                Text("До 100 недавних ответов хранятся в памяти 30 минут. «Обновить ответ» отправляет новый запрос. При выходе кэш очищается.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Очистить кэш ответов") { app.analysisService.clearCache(); notice = "Кэш очищен" }
            }
            Section("Разбор скопированного") {
                if let error = app.clipboardSettingsError { Text(error).foregroundStyle(.red) }
                Toggle("Включить разбор скопированного", isOn: Binding(
                    get: { app.settings.clipboardEnabled },
                    set: { value in perform { try app.setClipboard(enabled: value) } }))
                Toggle("Автоматически разбирать французский текст", isOn: Binding(
                    get: { app.settings.clipboardAutomatic },
                    set: { value in perform { try app.setClipboard(automatic: value) } }))
                Toggle("Показывать всплывающее окно", isOn: Binding(
                    get: { app.settings.clipboardShowPanel },
                    set: { value in perform { try app.setClipboard(showPanel: value) } }))
                Toggle("Сохранять историю разборов скопированного", isOn: Binding(
                    get: { app.settings.clipboardHistory },
                    set: { value in perform { try app.setClipboard(history: value) } }))
                Text("После включения проверяются только новые копирования. Язык определяется на этом Mac. Авторазбор отправляет вероятно французский текст до 500 символов в OpenAI; более длинный текст (до 4 000) требует нажатия «Разобрать». Не копируйте личные данные при включённом авторазборе: определение языка не распознаёт все секреты.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Если окно скрыто, последний текст или ответ можно открыть из меню DéjàVu. История записывается только при включённой общей истории. Произвольное содержимое буфера не сохраняется. Для чтения буфера не нужен доступ к Универсальному доступу или микрофону; если macOS запросит доступ к вставке, решение остаётся за вами.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Конфиденциальность") {
                Toggle("Сохранять историю успешных разборов", isOn: $saveHistory)
                    .onChange(of: saveHistory) { _, value in
                        guard value != app.settings.saveHistory else { return }
                        perform {
                            try app.settings.update(provider: app.settings.provider, model: app.settings.model, saveHistory: value)
                        }
                        saveHistory = app.settings.saveHistory
                    }
                Text("История и сохранённые выражения хранятся только на этом Mac. Если история выключена, разбор останется только на экране, пока вы сами его не сохраните.")
                Text("История включает до 100 успешных вопросов помощника и контекст уточнений. Она управляется тем же переключателем. Кэш ответов остаётся только в памяти; его можно очистить отдельно.")
                Text("Текст отправляется в OpenAI по вашему запросу или при включённом авторазборе скопированного. Сохранение ответа на стороне API отключено; обработка данных поставщиком регулируется его политикой.")
                Text("Буфер обмена проверяется только при включённом разборе скопированного. Доступ к микрофону, выделенному тексту и страницам браузера не запрашивается.")
                Button("Очистить историю…", role: .destructive) { clearConfirmation = true }
            }
            Section("О приложении") {
                LabeledContent("Приложение", value: "DéjàVu")
                LabeledContent("Версия", value: "0.3.0")
                Text("Французский для жизни. Для русскоязычного ученика A2 → B1.")
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            }
            if let notice {
                Section { Label(notice, systemImage: "checkmark.circle").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Настройки")
        .onAppear {
            provider = app.settings.provider
            model = app.settings.model
            saveHistory = app.settings.saveHistory
            perform { keyIsStored = try app.keychain.load() != nil }
        }
        .onDisappear {
            connectionTask?.cancel()
            newKey = ""
        }
        .onChange(of: app.settings.saveHistory) { _, value in saveHistory = value }
        .onChange(of: app.settings.model) { _, value in model = value }
        .onChange(of: app.settings.provider) { _, value in provider = value }
        .confirmationDialog("Очистить историю разборов?", isPresented: $clearConfirmation) {
            Button("Очистить историю", role: .destructive) {
                perform { try app.clearHistory(); notice = "История очищена" }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("История и несохранённые выражения будут удалены. Сохранённые выражения и заметки останутся.")
        }
    }

    private func saveSettings() {
        perform {
            try app.settings.update(provider: provider, model: model, saveHistory: app.settings.saveHistory)
            model = app.settings.model
            notice = "Настройки сохранены"
        }
    }

    private func perform(_ action: () throws -> Void) {
        errorMessage = nil
        notice = nil
        do { try action() } catch { errorMessage = AppError.message(for: error) }
    }

    private func testConnection() {
        testing = true
        errorMessage = nil
        notice = nil
        connectionTask = Task {
            defer { testing = false; connectionTask = nil }
            do {
                try await app.analysisService.testConnection()
                try Task.checkCancellation()
                notice = "Подключение работает. Разбор получен."
            } catch is CancellationError {
                notice = "Проверка отменена"
            } catch { errorMessage = AppError.message(for: error) }
        }
    }
}
