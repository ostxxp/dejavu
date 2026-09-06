import Foundation
import SwiftData

@MainActor final class HistoryStore {
    private let context: ModelContext
    private let vocabulary: VocabularyStore
    init(context: ModelContext, vocabulary: VocabularyStore) {
        self.context = context
        self.vocabulary = vocabulary
    }

    /// Only a successful, validated analysis is persisted; never raw input or failures.
    func record(_ analysis: FrenchAnalysis, source: AnalysisSource, now: Date = .now) throws {
        do {
            let analysis = try analysis.validated()
            let data = try JSONEncoder().encode(analysis)
            _ = try vocabulary.stageEncounter(analysis, source: source, now: now)
            context.insert(AnalysisHistoryEntry(analysis: analysis, source: source, data: data, now: now))
            try PersistenceController.save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func clear() throws {
        do {
            for entry in try context.fetch(FetchDescriptor<AnalysisHistoryEntry>()) { context.delete(entry) }
            // Keep explicitly saved vocabulary and personal notes.
            for entry in try context.fetch(FetchDescriptor<VocabularyEntry>(predicate: #Predicate { !$0.savedByUser })) {
                context.delete(entry)
            }
            try PersistenceController.save(context)
        } catch {
            context.rollback()
            throw AppError.storage
        }
    }
}
