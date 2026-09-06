import SwiftData
import SwiftUI

struct AnalysisView: View {
    let analysis: FrenchAnalysis
    let source: AnalysisSource
    @Environment(AppEnvironment.self) private var app
    @Query(filter: #Predicate<VocabularyEntry> { $0.savedByUser }) private var saved: [VocabularyEntry]
    @State private var errorMessage: String?

    private var isSaved: Bool {
        saved.contains { $0.normalizedForm == ExpressionNormalizer.normalize(analysis.original) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(analysis.original).font(.system(size: 27, weight: .medium, design: .serif))
                    if let ipa = analysis.ipa { Text(ipa).font(.title3).foregroundStyle(.secondary) }
                }
                Spacer()
                if let difficulty = analysis.difficulty {
                    Text(difficulty).font(.caption.weight(.medium)).padding(.horizontal, 9).padding(.vertical, 5)
                        .background(.quaternary, in: Capsule())
                }
            }
            Text(analysis.translation).font(.title3)
            if let lemma = analysis.lemma { metadata("Начальная форма", value: lemma) }
            if let part = analysis.partOfSpeech { metadata("Часть речи", value: part) }
            if let gender = analysis.gender { metadata("Род", value: gender) }
            if let article = analysis.article { metadata("Артикль", value: article) }
            if let plural = analysis.plural { metadata("Множественное число", value: plural) }
            if let verb = analysis.verbForm {
                Text("\(verb.infinitive) → \(verb.tense) · \(verb.person)").foregroundStyle(.secondary)
            }
            points(analysis.grammar, title: "Как это устроено")
            points(analysis.chunks, title: "Полезные конструкции")
            if !analysis.examples.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Примеры").font(.headline)
                    ForEach(Array(analysis.examples.enumerated()), id: \.offset) { _, example in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(example.fr)
                            Text(example.translation).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let notes = analysis.naturalnessNotes { Text(notes).foregroundStyle(.secondary) }
            Button(isSaved ? "Сохранено" : "Сохранить", systemImage: isSaved ? "bookmark.fill" : "bookmark") {
                do {
                    _ = try app.vocabulary.save(analysis, source: source)
                    errorMessage = nil
                } catch { errorMessage = AppError.message(for: error) }
            }
            .disabled(isSaved)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .textSelection(.enabled)
    }

    private func metadata(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label + ":").foregroundStyle(.secondary)
            Text(value)
        }.font(.callout)
    }

    @ViewBuilder private func points(_ items: [LearningPoint], title: String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                ForEach(Array(items.enumerated()), id: \.offset) { _, point in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(point.title).fontWeight(.medium)
                        Text(point.explanation).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
