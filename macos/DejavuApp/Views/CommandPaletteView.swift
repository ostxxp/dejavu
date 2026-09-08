import SwiftData
import SwiftUI

struct CommandPaletteView: View {
    let onClose: () -> Void
    let onResize: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Query(filter: #Predicate<VocabularyEntry> { $0.savedByUser }) private var saved: [VocabularyEntry]

    var body: some View {
        @Bindable var model = app.commandPaletteModel
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    if app.settings.mascotEnabled { DejaCompanion(compact: true) }
                    Text("DéjàVu").font(.system(.headline, design: .serif))
                    Text("Быстрый помощник").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .buttonStyle(.plain).help("Закрыть · Esc").accessibilityLabel("Закрыть помощник")
                }
                PaletteInput(text: $model.input,
                             placeholder: model.context == nil ? "Спросите что-нибудь о французском…" : "Уточните этот ответ…",
                             isEnabled: !model.isLoading && !model.completedFollowUp,
                             focusToken: model.focusToken,
                             onSubmit: { model.submit() }, onPrevious: { model.previousQuery() },
                             onNext: { model.nextQuery() }, onClose: onClose)
                    .frame(height: 30)
                HStack(spacing: 12) {
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                        Text("Разбираем…").foregroundStyle(.secondary)
                        Button("Отменить") { model.cancel() }
                    } else if model.completedFollowUp {
                        Text("Уточнение готово").foregroundStyle(.secondary)
                        Button("Новый вопрос") { model.clear() }
                    } else {
                        Button(model.context == nil ? "Разобрать" : "Уточнить") { model.submit() }
                            .buttonStyle(.borderedProminent).disabled(!model.canSubmit)
                        Text(model.context == nil ? "↵ отправить · ↑↓ история" : "Одно уточнение к предыдущему ответу")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !model.input.isEmpty {
                        Button("Очистить") { model.clear() }.help("Новый вопрос · ⌘K")
                    }
                }.controlSize(.small)
            }.padding(22)
            if model.result != nil || model.errorMessage != nil {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let error = model.errorMessage {
                            Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                            Button("Открыть настройки") {
                                onClose()
                                app.openSettingsWindow?()
                            }
                        }
                        if let result = model.result {
                            if model.fromCache {
                                Label("Недавний ответ · без нового запроса", systemImage: "clock.arrow.circlepath")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            AnalysisView(analysis: result, source: .commandPalette,
                                         compact: !model.showsDetails, showsActions: false)
                        }
                        if let notice = model.notice { Text(notice).font(.callout).foregroundStyle(.secondary) }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text("leur vs leurs · tu devrais · как сказать «оба»")
                        .foregroundStyle(.secondary)
                    Text("Текст отправляется в OpenAI только после отправки вопроса.")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                Spacer(minLength: 12)
            }
            if let result = model.result {
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Button("Прослушать", systemImage: "speaker.wave.2") { model.listen() }.help("Прослушать · ⌘L")
                        Button(isSaved(result) ? "Сохранено" : "Сохранить", systemImage: isSaved(result) ? "bookmark.fill" : "bookmark") {
                            model.save()
                        }.disabled(isSaved(result)).help("Сохранить · ⌘S")
                        Button(model.showsDetails ? "Свернуть" : "Подробнее") { model.showsDetails.toggle() }
                        Spacer(minLength: 0)
                    }.disabled(model.isLoading)
                    HStack {
                        if model.canFollowUp { Button("Задать уточнение") { model.beginFollowUp() } }
                        if app.speech.isSpeaking { Button("Остановить звук") { app.speech.stop() } }
                        Spacer()
                        Button("Обновить ответ") { model.refresh() }
                            .disabled(model.isLoading || model.lastRequest == nil)
                            .help("Отправить запрос заново, не используя кэш")
                    }
                }.controlSize(.small).padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onChange(of: model.preferredHeight) { _, _ in onResize() }
    }

    private func isSaved(_ analysis: FrenchAnalysis) -> Bool {
        saved.contains { $0.normalizedForm == ExpressionNormalizer.normalize(analysis.original) }
    }
}
