import Foundation
import SwiftData

@MainActor final class HistoryStore {
    private let context: ModelContext
    private let vocabulary: VocabularyStore
    private let commandHistory: CommandPaletteHistoryStore
    init(context: ModelContext, vocabulary: VocabularyStore) {
        self.context = context
        self.vocabulary = vocabulary
        commandHistory = CommandPaletteHistoryStore(context: context)
    }

    /// Persist successful analyses and optional validated command queries atomically; never failures.
    func record(_ analysis: FrenchAnalysis, source: AnalysisSource, now: Date = .now,
                request: AnalysisRequest? = nil) throws {
        do {
            let analysis = try analysis.validated()
            let data = try JSONEncoder().encode(analysis)
            _ = try vocabulary.stageEncounter(analysis, source: source, now: now)
            context.insert(AnalysisHistoryEntry(analysis: analysis, source: source, data: data, now: now))
            if let request { try commandHistory.stage(request, now: now) }
            try PersistenceController.save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func clear() throws {
        do {
            for entry in try context.fetch(FetchDescriptor<AnalysisHistoryEntry>()) { context.delete(entry) }
            for entry in try context.fetch(FetchDescriptor<CommandPaletteHistoryEntry>()) { context.delete(entry) }
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
