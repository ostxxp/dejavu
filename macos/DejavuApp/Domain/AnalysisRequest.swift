import CryptoKit
import Foundation

struct AnalysisRequest: Codable, Equatable, Sendable {
    var query: String
    var context: FollowUpContext? = nil

    func validated() throws -> Self {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 4_000 else { throw AppError.invalidInput }
        if let context {
            guard context.originalQuery.count <= 4_000 else { throw AppError.invalidInput }
            _ = try context.analysis.validated()
            guard try JSONEncoder().encode(context).count <= 64_000 else { throw AppError.invalidInput }
        }
        return Self(query: query, context: context)
    }

    /// A stable identity for lookups, preserving case, accents and context.
    func fingerprint() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(validated())).map { String(format: "%02x", $0) }.joined()
    }
}

struct FollowUpContext: Codable, Equatable, Sendable {
    var originalQuery: String
    var analysis: FrenchAnalysis
}

struct AnalysisOutcome: Sendable {
    let analysis: FrenchAnalysis
    let fromCache: Bool
}

@MainActor protocol LanguageAnalyzing {
    func analyze(_ request: AnalysisRequest, forceRefresh: Bool) async throws -> AnalysisOutcome
}
