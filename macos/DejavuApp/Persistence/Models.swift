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
    var analysis: FrenchAnalysis? { try? JSONDecoder().decode(FrenchAnalysis.self, from: analysisData).validated() }

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
    var analysis: FrenchAnalysis? { try? JSONDecoder().decode(FrenchAnalysis.self, from: analysisData).validated() }

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
    var bridgeEnabled: Bool = false
    var bridgeExtensionID: String = ""
    var welcomeCompleted: Bool = true
    var accentRaw: String = "lavender"
    var playfulDetails: Bool = true
    var dialogueEnabled: Bool = false
    var dialogueMinutes: Int = 45
    var dialoguePausedUntil: Date?
    var dialogueReuseVocabulary: Bool = true
    var clipboardEnabled: Bool = false
    var clipboardAutomatic: Bool = false
    var clipboardShowPanel: Bool = true
    var clipboardHistory: Bool = true

    init() {
        identifier = "default"
        welcomeCompleted = false
        providerRaw = AIProvider.openAI.rawValue
        model = "gpt-4o-mini"
        saveHistory = true
    }
}

@Model final class CommandPaletteHistoryEntry {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var fingerprint: String
    var query: String
    var requestData: Data
    var lastUsedAt: Date

    var request: AnalysisRequest? { try? JSONDecoder().decode(AnalysisRequest.self, from: requestData) }

    init(request: AnalysisRequest, fingerprint: String, data: Data, now: Date) {
        id = UUID()
        self.fingerprint = fingerprint
        query = request.query
        requestData = data
        lastUsedAt = now
    }
}
