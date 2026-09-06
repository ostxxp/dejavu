import SwiftData
import SwiftUI

struct SavedView: View {
    @Query(filter: #Predicate<VocabularyEntry> { $0.savedByUser }, sort: \VocabularyEntry.lastSeenAt, order: .reverse)
    private var entries: [VocabularyEntry]
    @State private var search = ""
    @State private var selected: VocabularyEntry?

    private var filtered: [VocabularyEntry] {
        entries.filter { search.isEmpty || $0.french.localizedStandardContains(search)
            || $0.russianMeaning.localizedStandardContains(search) || $0.notes.localizedStandardContains(search) }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView("Здесь будет ваш французский", systemImage: "bookmark",
                                       description: Text("Сохраните полезное выражение после разбора — оно останется на этом Mac."))
            } else if filtered.isEmpty {
                ContentUnavailableView("Ничего не найдено", systemImage: "magnifyingglass",
                                       description: Text("Попробуйте другое слово или перевод."))
            } else {
                List(filtered) { entry in
                    Button { selected = entry } label: {
                        LibraryRow(french: entry.french, translation: entry.russianMeaning,
                                   source: entry.source.title, date: entry.lastSeenAt)
                    }.buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Сохранённое")
        .searchable(text: $search, prompt: "Найти выражение, перевод или заметку")
        .sheet(item: $selected) { entry in
            LibraryDetail(analysis: entry.analysis, source: entry.source, entry: entry)
        }
    }
}

struct HistoryView: View {
    @Query(sort: \AnalysisHistoryEntry.createdAt, order: .reverse) private var entries: [AnalysisHistoryEntry]
    @State private var search = ""
    @State private var selected: AnalysisHistoryEntry?
    private var filtered: [AnalysisHistoryEntry] {
        entries.filter { search.isEmpty || $0.french.localizedStandardContains(search)
            || $0.translation.localizedStandardContains(search) }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView("Пока без истории", systemImage: "clock.arrow.circlepath",
                                       description: Text("Здесь появятся успешные разборы, если сохранение истории включено в настройках."))
            } else if filtered.isEmpty {
                ContentUnavailableView("Ничего не найдено", systemImage: "magnifyingglass",
                                       description: Text("Попробуйте другое слово или перевод."))
            } else {
                List(filtered) { entry in
                    Button { selected = entry } label: {
                        LibraryRow(french: entry.french, translation: entry.translation,
                                   source: entry.source.title, date: entry.createdAt)
                    }.buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("История")
        .searchable(text: $search, prompt: "Найти выражение или перевод")
        .sheet(item: $selected) { entry in
            LibraryDetail(analysis: entry.analysis, source: entry.source)
        }
    }
}

private struct LibraryRow: View {
    let french: String
    let translation: String
    let source: String
    let date: Date
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(french).font(.title3.weight(.medium)).lineLimit(2)
                Text(translation).foregroundStyle(.secondary).lineLimit(2)
                Text(source).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct LibraryDetail: View {
    let analysis: FrenchAnalysis?
    let source: AnalysisSource
    var entry: VocabularyEntry?
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var notice: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(source.title).foregroundStyle(.secondary)
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let analysis { AnalysisView(analysis: analysis, source: source) }
                    else { Text("Не удалось прочитать этот разбор.").foregroundStyle(.secondary) }
                    if let entry {
                        Divider()
                        Text("Моя заметка").font(.headline)
                        TextField("Что хочется запомнить?", text: $notes, axis: .vertical)
                            .lineLimit(3...8).textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Сохранить заметку") {
                                do {
                                    try app.vocabulary.update(entry, saved: true, notes: notes)
                                    notice = "Заметка сохранена"
                                    errorMessage = nil
                                } catch { errorMessage = AppError.message(for: error) }
                            }
                            Spacer()
                            Button("Убрать из сохранённого", role: .destructive) {
                                do {
                                    try app.vocabulary.update(entry, saved: false, notes: notes)
                                    dismiss()
                                } catch { errorMessage = AppError.message(for: error) }
                            }
                        }
                    }
                    if let notice { Text(notice).font(.callout).foregroundStyle(.secondary) }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }.padding(28)
            }
        }
        .frame(width: 620, height: 680)
        .onAppear { notes = entry?.notes ?? "" }
    }
}
