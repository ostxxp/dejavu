import Foundation

@MainActor final class AnalysisCache {
    struct Key: Hashable {
        let provider: String
        let model: String
        let requestFingerprint: String
    }

    private struct Entry {
        let analysis: FrenchAnalysis
        let expiresAt: Date
        var lastAccess: UInt64
    }

    private let capacity: Int
    private let lifetime: TimeInterval
    private let now: () -> Date
    private var entries: [Key: Entry] = [:]
    private var sequence: UInt64 = 0
    private(set) var generation = 0

    init(capacity: Int = 100, lifetime: TimeInterval = 30 * 60, now: @escaping () -> Date = Date.init) {
        self.capacity = max(1, capacity)
        self.lifetime = max(0, lifetime)
        self.now = now
    }

    func value(for key: Key) -> FrenchAnalysis? {
        purgeExpired()
        guard var entry = entries[key] else { return nil }
        sequence += 1
        entry.lastAccess = sequence
        entries[key] = entry
        return entry.analysis
    }

    func insert(_ analysis: FrenchAnalysis, for key: Key) {
        purgeExpired()
        sequence += 1
        entries[key] = Entry(analysis: analysis, expiresAt: now().addingTimeInterval(lifetime), lastAccess: sequence)
        if entries.count > capacity, let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            entries.removeValue(forKey: oldest)
        }
    }

    func clear() {
        entries.removeAll()
        generation += 1
    }

    private func purgeExpired() {
        let current = now()
        entries = entries.filter { $0.value.expiresAt > current }
    }
}
