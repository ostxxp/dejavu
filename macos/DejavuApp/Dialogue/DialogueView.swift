import SwiftUI
import AppKit

struct DialogueView: View {
    @Environment(AppEnvironment.self) private var app
    @FocusState private var writing: Bool
    var body: some View {
        @Bindable var dialogue = app.dialogue
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if app.settings.mascotEnabled { DejaCompanion(compact: true) }
                VStack(alignment: .leading) {
                    Text("DéjàVu").font(.system(.title2, design: .serif))
                    Text(dialogue.activeCollection?.title ?? "Минутка французского").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dialogue.close() } label: { Image(systemName: "xmark") }.help("Закрыть мини-диалог").accessibilityLabel("Закрыть мини-диалог")
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let scenario = dialogue.scenario {
                        Text(scenario.situation).font(.callout).foregroundStyle(.secondary)
                        Text(scenario.question).font(.system(.title2, design: .serif))
                        Button("Прослушать вопрос", systemImage: "speaker.wave.2") { speak(scenario.question) }
                            .disabled(app.dialogueVoice.recording || app.dialogueVoice.requesting)
                        if let feedback = dialogue.feedback {
                            Label(feedback.isNatural ? "Звучит естественно" : (feedback.understood ? "Смысл понятен" : "Давайте уточним мысль"),
                                  systemImage: feedback.understood ? "checkmark.circle" : "bubble.left")
                                .font(.headline)
                            if !feedback.isNatural {
                                if let corrected = feedback.correctedVersion { item("С поправкой", corrected) }
                                if let natural = feedback.moreNaturalVersion { item("Естественнее", natural) }
                                if let issue = feedback.mainIssue { Text(issue).font(.callout) }
                            }
                            item("Полезно", feedback.usefulPhrase)
                            Text(feedback.usefulTranslation).foregroundStyle(.secondary)
                            Text(feedback.encouragement).font(.callout)
                            HStack {
                                Button(dialogue.saved ? "Сохранено" : "Сохранить фразу") { dialogue.savePhrase() }.disabled(dialogue.saved)
                                Button("Прослушать") { speak(feedback.usefulPhrase) }
                            }
                            Button("Готово") { dialogue.close() }.buttonStyle(.borderedProminent)
                        } else {
                            HStack {
                                Button(app.dialogueVoice.recording ? "Остановить запись" : "Ответить голосом", systemImage: "mic") {
                                    if app.dialogueVoice.recording { app.dialogueVoice.stop() }
                                    else { app.speech.stop(); Task { await app.dialogueVoice.start() } }
                                }.disabled(dialogue.isLoading || app.dialogueVoice.requesting)
                                Button("Написать") { app.dialogueVoice.stop(); writing = true }
                            }
                            if app.dialogueVoice.recording { Label("Слушаю… до одной минуты", systemImage: "record.circle").foregroundStyle(.red) }
                            if app.dialogueVoice.requesting { Text("Ожидаем разрешение macOS…").font(.caption) }
                            TextEditor(text: $dialogue.answer).frame(minHeight: 90, maxHeight: 120)
                                .focused($writing).disabled(dialogue.isLoading || app.dialogueVoice.recording)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                                .accessibilityLabel("Ваш ответ по-французски")
                            Text("Можно исправить расшифровку перед отправкой. Ответ отправится в ИИ только по кнопке ниже.").font(.caption).foregroundStyle(.secondary)
                            Button("Отправить ответ") { app.dialogueVoice.stop(); dialogue.submit() }
                                .buttonStyle(.borderedProminent)
                                .disabled(dialogue.isLoading || app.dialogueVoice.recording || app.dialogueVoice.requesting || dialogue.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    if dialogue.isLoading { ProgressView(dialogue.scenario == nil ? "Готовим ситуацию…" : "Читаем ваш ответ…") }
                    if let message = dialogue.errorMessage {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                        if dialogue.scenario == nil && !dialogue.isLoading {
                            Button("Повторить") { dialogue.close(); app.dialogueController.triggerNow() }
                        }
                        Button("Открыть настройки") { app.openSettingsWindow?() }
                    }
                    if let message = app.dialogueVoice.errorMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("Отложить на час") { app.dialogueController.pause(until: .now.addingTimeInterval(3600)) }
                Spacer()
                Button("До завтра") { app.dialogueController.pause(until: DialogueTiming.tomorrow(now: .now)) }
                    .help("Приостановить до завтра")
            }.font(.caption).padding(16)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .onChange(of: app.dialogueVoice.transcript) { _, text in if !text.isEmpty { dialogue.answer = text } }
        .onDisappear { app.dialogueVoice.clear() }
    }
    private func item(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(label).font(.caption).foregroundStyle(.secondary); Text(text).textSelection(.enabled) }
    }
    private func speak(_ text: String) {
        do { try app.speech.speak(text) } catch { app.dialogue.errorMessage = AppError.message(for: error) }
    }
}

struct DialogueSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var minutes = 45
    @State private var preset = 45
    var body: some View {
        Section("Мини-диалоги") {
            Picker("Тема", selection: Binding(get: { app.settings.dialogueCollection }, set: { value in
                do { try app.settings.setDialogueCollection(value) }
                catch { app.dialogueSettingsError = AppError.message(for: error) }
            })) {
                Text("Любая ситуация").tag(Optional<VocabularyCollection>.none)
                ForEach(VocabularyCollection.allCases) { Text($0.title).tag(Optional($0)) }
            }
            Text("Новая тема применяется к следующему диалогу. Сохранённая из него фраза попадёт в выбранную коллекцию.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Предлагать мини-диалоги", isOn: Binding(get: { app.settings.dialogueEnabled }, set: {
                app.dialogueController.configure(enabled: $0, minutes: app.settings.dialogueMinutes, reuse: app.settings.dialogueReuseVocabulary)
            }))
            Picker("Частота", selection: $preset) {
                ForEach([20, 30, 45, 60], id: \.self) { Text("\($0) минут").tag($0) }
                Text("Другая").tag(0)
            }.onChange(of: preset) { _, value in if value != 0 { minutes = value; saveInterval() } }
            if preset == 0 {
                HStack { TextField("Минуты (10–240)", value: $minutes, format: .number); Button("Сохранить интервал") { saveInterval() } }
            }
            Toggle("Использовать сохранённые выражения", isOn: Binding(get: { app.settings.dialogueReuseVocabulary }, set: {
                app.dialogueController.configure(enabled: app.settings.dialogueEnabled, minutes: app.settings.dialogueMinutes, reuse: $0)
            }))
            Text("При включении приложение иногда отправляет запрос на новую ситуацию в ИИ, когда Mac активен. Для ситуации могут использоваться до пяти сохранённых выражений. После ответа в ИИ отправляются вопрос и ваш текст. Диалоги и аудио на диск не записываются; фраза сохраняется только по вашей кнопке.").font(.caption).foregroundStyle(.secondary)
            Text("Голос включается только по нажатию и распознаётся локально на французском. Если распознавание недоступно, можно написать ответ. Интервал приблизительный: во время простоя, блокировки, полноэкранного окна или некоторых приложений для встреч появление откладывается.").font(.caption).foregroundStyle(.secondary)
            if let date = app.settings.dialoguePausedUntil, date > .now {
                Text("Пауза до \(date.formatted(date: .abbreviated, time: .shortened))")
                Button("Снять паузу") { app.dialogueController.pause(until: nil) }
            }
            HStack {
                Button("Отложить на час") { app.dialogueController.pause(until: .now.addingTimeInterval(3600)) }
                Button("Приостановить до завтра") { app.dialogueController.pause(until: DialogueTiming.tomorrow(now: .now)) }
            }
            Text("Разрешения находятся в разделе macOS «Конфиденциальность и безопасность»: «Микрофон» и «Распознавание речи».").font(.caption).foregroundStyle(.secondary)
            Text(app.dialogueVoice.permissionDescription).font(.caption).foregroundStyle(.secondary)
            Button("Открыть настройки macOS") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            }
            Button("Начать мини-диалог") { app.dialogueController.triggerNow() }
            Text("Ручной запуск отправляет один запрос в ИИ даже при выключенном расписании.").font(.caption).foregroundStyle(.secondary)
            if let message = app.dialogueSettingsError { Text(message).foregroundStyle(.red) }
        }.onAppear { minutes = app.settings.dialogueMinutes; preset = [20,30,45,60].contains(minutes) ? minutes : 0 }
    }
    private func saveInterval() {
        app.dialogueController.configure(enabled: app.settings.dialogueEnabled, minutes: minutes, reuse: app.settings.dialogueReuseVocabulary)
    }
}
