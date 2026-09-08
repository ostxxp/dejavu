import SwiftData
import SwiftUI

struct SavedView: View {
    @Environment(AppEnvironment.self) private var app
    @Query(filter: #Predicate<VocabularyEntry> { $0.savedByUser }, sort: \VocabularyEntry.lastSeenAt, order: .reverse)
    private var entries: [VocabularyEntry]
    @State private var search = ""
    @State private var collection: VocabularyCollection?
    @State private var collectionError: String?
    @State private var selected: VocabularyEntry?

    private var filtered: [VocabularyEntry] {
        entries.filter { (collection == nil || $0.collection == collection) &&
            (search.isEmpty || $0.french.localizedStandardContains(search)
            || $0.russianMeaning.localizedStandardContains(search) || $0.notes.localizedStandardContains(search)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            collectionBar
            savedContent.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Сохранённое")
        .searchable(text: $search, prompt: "Найти выражение, перевод или заметку")
        .sheet(item: $selected) { entry in
            LibraryDetail(analysis: entry.analysis, source: entry.source, entry: entry)
        }
    }
    private var savedContent: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Здесь будет ваш французский", systemImage: "bookmark")
                } description: {
                    Text("Сохраните полезное выражение после разбора — оно останется на этом Mac.")
                } actions: {
                    Button("Разобрать выражение") { app.section = .home }
                }
            } else if filtered.isEmpty {
                ContentUnavailableView(collection == nil ? "Ничего не найдено" : "Коллекция ждёт свои фразы", systemImage: collection?.symbol ?? "magnifyingglass",
                                       description: Text("Откройте сохранённое выражение и выберите для него коллекцию. Попробуйте изменить поиск или выбрать «Все»."))
            } else {
                List(filtered) { entry in
                    Button { selected = entry } label: {
                        LibraryRow(french: entry.french, translation: entry.russianMeaning,
                                   source: entry.collection.map { "\($0.title) · \(entry.source.title)" } ?? entry.source.title, date: entry.lastSeenAt)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var collectionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    collectionButton(nil)
                    ForEach(VocabularyCollection.allCases) { collectionButton($0) }
                }
            }.fixedSize(horizontal: false, vertical: true)
            if let collection {
                Button("Мини-диалог: \(collection.title)", systemImage: "bubble.left.and.bubble.right") {
                    do {
                        try app.settings.setDialogueCollection(collection)
                        app.dialogue.close()
                        app.dialogueController.triggerNow()
                    } catch { collectionError = AppError.message(for: error) }
                }
            }
            if let collectionError { Text(collectionError).foregroundStyle(.red).font(.caption) }
        }.padding(16).background(.bar)
    }

    private func collectionButton(_ value: VocabularyCollection?) -> some View {
        Button { collection = value } label: {
            Label(value?.title ?? "Все", systemImage: value?.symbol ?? "square.grid.2x2")
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(collection == value ? app.settings.accent.color.opacity(0.18) : .clear, in: Capsule())
        }.buttonStyle(.plain).accessibilityValue(collection == value ? "Выбрано" : "")
    }
}

struct HistoryView: View {
    @Environment(AppEnvironment.self) private var app
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
                                       description: Text(app.settings.saveHistory ? "Здесь появятся успешные разборы. Начните с выражения на главной." : "Сохранение истории выключено. Его можно включить в настройках; сохранённые выражения остаются в словаре."))
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
                        Picker("Коллекция", selection: Binding(get: { entry.collection }, set: { value in
                            do { try app.vocabulary.setCollection(entry, collection: value); errorMessage = nil }
                            catch { errorMessage = AppError.message(for: error) }
                        })) {
                            Text("Без коллекции").tag(Optional<VocabularyCollection>.none)
                            ForEach(VocabularyCollection.allCases) { Text($0.title).tag(Optional($0)) }
                        }
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
