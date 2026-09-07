import Foundation
import SwiftData

@MainActor final class VocabularyStore {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func dialogueVocabulary() throws -> [String] {
        var descriptor = FetchDescriptor<VocabularyEntry>(predicate: #Predicate { $0.savedByUser },
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)])
        descriptor.fetchLimit = 30
        let entries = try context.fetch(descriptor).filter { $0.french.count <= 160 }
        // Mix recent items with a frequently encountered expression, never notes or raw queries.
        var result = Array(entries.prefix(4).map(\.french))
        if let frequent = entries.max(by: { $0.seenCount < $1.seenCount }), !result.contains(frequent.french) { result.append(frequent.french) }
        return result
    }

    func find(_ french: String) throws -> VocabularyEntry? {
        let normalized = ExpressionNormalizer.normalize(french)
        var descriptor = FetchDescriptor<VocabularyEntry>(predicate: #Predicate { $0.normalizedForm == normalized })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// An encounter increments the count. Saving an existing entry does not.
    @discardableResult
    func recordEncounter(_ analysis: FrenchAnalysis, source: AnalysisSource, now: Date = .now) throws -> VocabularyEntry {
        let entry = try stageEncounter(analysis, source: source, now: now)
        try PersistenceController.save(context)
        return entry
    }

    @discardableResult
    func save(_ analysis: FrenchAnalysis, source: AnalysisSource) throws -> VocabularyEntry {
        let entry: VocabularyEntry
        if let existing = try find(analysis.original) {
            entry = existing
        } else {
            entry = try stageEncounter(analysis, source: source, now: .now)
        }
        entry.savedByUser = true
        try PersistenceController.save(context)
        return entry
    }

    func update(_ entry: VocabularyEntry, saved: Bool, notes: String) throws {
        entry.savedByUser = saved
        entry.notes = notes
        try PersistenceController.save(context)
    }

    /// Used by HistoryStore to commit both records atomically in the shared context.
    func stageEncounter(_ analysis: FrenchAnalysis, source: AnalysisSource, now: Date) throws -> VocabularyEntry {
        let analysis = try analysis.validated()
        if let entry = try find(analysis.original) {
            var merged = entry.analysis ?? analysis
            merged.ipa = merged.ipa ?? analysis.ipa
            merged.lemma = merged.lemma ?? analysis.lemma
            merged.partOfSpeech = merged.partOfSpeech ?? analysis.partOfSpeech
            merged.gender = merged.gender ?? analysis.gender
            merged.article = merged.article ?? analysis.article
            merged.plural = merged.plural ?? analysis.plural
            merged.verbForm = merged.verbForm ?? analysis.verbForm
            merged.difficulty = merged.difficulty ?? analysis.difficulty
            merged.naturalnessNotes = merged.naturalnessNotes ?? analysis.naturalnessNotes
            if merged.examples.isEmpty { merged.examples = analysis.examples }
            if merged.grammar.isEmpty { merged.grammar = analysis.grammar }
            if merged.chunks.isEmpty { merged.chunks = analysis.chunks }
            let data = try JSONEncoder().encode(merged)
            entry.analysisData = data
            entry.ipa = merged.ipa
            entry.lemma = merged.lemma
            entry.partOfSpeech = merged.partOfSpeech
            entry.exampleSentence = merged.examples.first?.fr
            entry.difficulty = merged.difficulty
            entry.seenCount += 1
            entry.lastSeenAt = max(entry.lastSeenAt, now)
            return entry
        }
        let entry = VocabularyEntry(analysis: analysis, source: source,
                                    data: try JSONEncoder().encode(analysis), now: now)
        context.insert(entry)
        return entry
    }
}
