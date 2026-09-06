import Foundation
import SwiftData

@Model final class VocabularyEntry {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var normalizedForm: String
    var french: String
    var ipa: String?
    var russianMeaning: String
    var lemma: String?
    var partOfSpeech: String?
    var exampleSentence: String?
    var sourceRaw: String
    var createdAt: Date
    var lastSeenAt: Date
    var seenCount: Int
    var savedByUser: Bool
    var difficulty: String?
    var notes: String
    var analysisData: Data

    var source: AnalysisSource { AnalysisSource(rawValue: sourceRaw) ?? .manual }
    var analysis: FrenchAnalysis? { try? JSONDecoder().decode(FrenchAnalysis.self, from: analysisData) }

    init(analysis: FrenchAnalysis, source: AnalysisSource, data: Data, now: Date) {
        id = UUID()
        normalizedForm = ExpressionNormalizer.normalize(analysis.original)
        french = analysis.original
        ipa = analysis.ipa
        russianMeaning = analysis.translation
        lemma = analysis.lemma
        partOfSpeech = analysis.partOfSpeech
        exampleSentence = analysis.examples.first?.fr
        sourceRaw = source.rawValue
        createdAt = now
        lastSeenAt = now
        seenCount = 1
        savedByUser = false
        difficulty = analysis.difficulty
        notes = ""
        analysisData = data
    }
}

@Model final class AnalysisHistoryEntry {
    @Attribute(.unique) var id: UUID
    var french: String
    var translation: String
    var sourceRaw: String
    var createdAt: Date
    var analysisData: Data

    var source: AnalysisSource { AnalysisSource(rawValue: sourceRaw) ?? .manual }
    var analysis: FrenchAnalysis? { try? JSONDecoder().decode(FrenchAnalysis.self, from: analysisData) }

    init(analysis: FrenchAnalysis, source: AnalysisSource, data: Data, now: Date) {
        id = UUID()
        french = analysis.original
        translation = analysis.translation
        sourceRaw = source.rawValue
        createdAt = now
        analysisData = data
    }
}

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI
    var id: String { rawValue }
    var title: String { "OpenAI" }
}

@Model final class AppSettings {
    @Attribute(.unique) var identifier: String
    var providerRaw: String
    var model: String
    var saveHistory: Bool

    init() {
        identifier = "default"
        providerRaw = AIProvider.openAI.rawValue
        model = "gpt-4o-mini"
        saveHistory = true
    }
}
