import Foundation

struct FrenchAnalysis: Codable, Equatable, Sendable {
    var original: String
    var translation: String
    var ipa: String?
    var lemma: String?
    var partOfSpeech: String?
    var gender: String?
    var article: String?
    var plural: String?
    var verbForm: VerbForm?
    var grammar: [LearningPoint]
    var chunks: [LearningPoint]
    var examples: [FrenchExample]
    var difficulty: String?
    var naturalnessNotes: String?
    var suggestedCollection: String? = nil

    func validated() throws -> Self {
        guard !ExpressionNormalizer.normalize(original).isEmpty,
              original.count <= 4_000,
              !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              grammar.count <= 4, chunks.count <= 4, examples.count <= 2 else {
            throw AppError.invalidResponse
        }
        var result = self
        if let value = suggestedCollection, VocabularyCollection(rawValue: value) == nil {
            result.suggestedCollection = nil
        }
        result.ipa = Self.present(ipa)
        result.lemma = Self.present(lemma)
        result.partOfSpeech = Self.present(partOfSpeech)
        result.gender = Self.present(gender)
        result.article = Self.present(article)
        result.plural = Self.present(plural)
        result.difficulty = Self.present(difficulty)
        result.naturalnessNotes = Self.present(naturalnessNotes)
        if let form = verbForm, Self.present(form.infinitive) == nil || Self.present(form.tense) == nil || Self.present(form.person) == nil {
            result.verbForm = nil
        }
        return result
    }

    /// Some providers emit a literal "null" string despite nullable schema fields.
    private static func present(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.lowercased() != "null", value.lowercased() != "nil" else { return nil }
        return value
    }
}

struct VerbForm: Codable, Equatable, Sendable {
    var infinitive: String
    var tense: String
    var person: String
}

struct LearningPoint: Codable, Equatable, Sendable {
    var title: String
    var explanation: String
}

struct FrenchExample: Codable, Equatable, Sendable {
    var fr: String
    var translation: String
}

enum AnalysisSource: String, Codable, CaseIterable, Sendable {
    case manual
    case chromePopup = "chrome_popup"
    case clipboard
    case commandPalette = "command_palette"
    case conversationGhost = "conversation_ghost"

    var title: String {
        switch self {
        case .manual: "Ручной разбор"
        case .chromePopup: "Выделенный текст"
        case .clipboard: "Скопированный текст"
        case .commandPalette: "Быстрый помощник"
        case .conversationGhost: "Мини-диалог"
        }
    }
}

enum ExpressionNormalizer {
    /// Preserve accents, ligatures, punctuation and meaningful French spelling.
    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased(with: Locale(identifier: "fr_FR"))
    }
}
