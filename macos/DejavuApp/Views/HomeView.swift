import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var app
    @Query(sort: \AnalysisHistoryEntry.createdAt, order: .reverse) private var history: [AnalysisHistoryEntry]
    @Query(filter: #Predicate<VocabularyEntry> { $0.savedByUser }) private var saved: [VocabularyEntry]

    var body: some View {
        @Bindable var model = app.manualAnalysis
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Французский, который остаётся с вами.")
                        .font(.system(size: 28, weight: .medium, design: .serif))
                    Text("Разберите выражение. Заметьте закономерность. Сохраните полезное.")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
                    Label("Разобрано сегодня: \(history.filter { Calendar.current.isDateInToday($0.createdAt) }.count)", systemImage: "text.bubble")
                    Label("Сохранено: \(saved.count)", systemImage: "bookmark")
                }.font(.callout).foregroundStyle(.secondary)

                Button("Как пользоваться DéjàVu", systemImage: "questionmark.circle") { app.showWelcome = true }

                Button("Открыть быстрый помощник · ⌘⇧F", systemImage: "text.magnifyingglass") {
                    app.commandPalette.show()
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Ручной разбор").font(.title3.weight(.semibold))
                    Text("Выражение или вопрос о французском").font(.callout).foregroundStyle(.secondary)
                    TextField("Например: tu devrais или leur и leurs", text: $model.input, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .padding(16)
                        .background(.background, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                        .accessibilityLabel("Текст для разбора")
                    HStack {
                        if model.isLoading {
                            ProgressView().controlSize(.small)
                            Text("Разбираем…").foregroundStyle(.secondary)
                            Button("Отменить") { model.cancel() }
                        } else {
                            Button("Разобрать", systemImage: "arrow.up") { model.analyze() }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.input.count > 4_000)
                        }
                        Spacer()
                        Text("\(model.input.count) / 4 000").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("По нажатию «Разобрать» введённый текст отправится в OpenAI. Не вводите личные данные и секреты.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                            .textSelection(.enabled)
                        Button("Открыть настройки") { app.section = .settings }
                    }
                }
                if let result = model.result {
                    Divider()
                    AnalysisView(analysis: result, source: .manual).id(result.original)
                } else if !model.isLoading && !history.isEmpty {
                    Divider()
                    Text("Последнее").font(.headline)
                    ForEach(history.prefix(3)) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.french).font(.body.weight(.medium))
                                Text(item.translation).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.createdAt, style: .date).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    Button("Открыть историю") { app.section = .history }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Главная")
    }
}
