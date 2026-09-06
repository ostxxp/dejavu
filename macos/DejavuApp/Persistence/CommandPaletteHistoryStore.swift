import Foundation
import SwiftData

@MainActor final class CommandPaletteHistoryStore {
    private let context: ModelContext
    private let capacity: Int

    init(context: ModelContext, capacity: Int = 100) {
        self.context = context
        self.capacity = max(1, capacity)
    }

    func recentRequests() throws -> [AnalysisRequest] {
        var descriptor = FetchDescriptor<CommandPaletteHistoryEntry>(sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)])
        descriptor.fetchLimit = capacity
        return try context.fetch(descriptor).compactMap(\.request)
    }

    /// Participates in HistoryStore's transaction; only successful requests are staged.
    func stage(_ request: AnalysisRequest, now: Date) throws {
        let request = try request.validated()
        let fingerprint = try request.fingerprint()
        let data = try JSONEncoder().encode(request)
        var descriptor = FetchDescriptor<CommandPaletteHistoryEntry>(predicate: #Predicate { $0.fingerprint == fingerprint })
        descriptor.fetchLimit = 1
        if let entry = try context.fetch(descriptor).first {
            entry.lastUsedAt = now
        } else {
            context.insert(CommandPaletteHistoryEntry(request: request, fingerprint: fingerprint, data: data, now: now))
        }
        let all = try context.fetch(FetchDescriptor<CommandPaletteHistoryEntry>(sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]))
        for entry in all.dropFirst(capacity) { context.delete(entry) }
    }
}
