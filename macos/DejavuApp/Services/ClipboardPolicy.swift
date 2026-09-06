import CryptoKit
import Foundation
import NaturalLanguage

/// Local gate only. No input or fingerprints are persisted or logged.
struct ClipboardPolicy {
    static func candidate(_ raw: String, confidence: (String) -> Double = frenchConfidence) -> String? {
        guard raw.utf8.count <= 24_000 else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...4_000).contains(text.count),
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.subtracting(.newlines).contains($0) }),
              !isSensitiveOrTechnical(text), confidence(text) >= 0.8 else { return nil }
        return text
    }

    static func frenchConfidence(_ text: String) -> Double {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard recognizer.dominantLanguage == .french else { return 0 }
        return recognizer.languageHypotheses(withMaximum: 3)[.french] ?? 0
    }

    private static func isSensitiveOrTechnical(_ text: String) -> Bool {
        let patterns = [
            #"(?i)([a-z][a-z0-9+.-]*://|www\.|\b\S+@\S+\.\S+|-----BEGIN|\bBearer\s|\bsk-|\bgh[pousr]_|github_pat_|\bxox[baprs]-)"#,
            #"(?i)(password|mot de passe|api[_ -]?key|secret|token|пароль|ключ доступа)\s*[:=]"#,
            #"\b[A-Za-z0-9_+/=-]{32,}\b"#,
            #"\d{6,}"#,
            #"[{}]|\b(?:import|function|const|SELECT)\s"#
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }
}

struct ClipboardDuplicates {
    private var seen: [String: Date] = [:]
    mutating func accept(_ text: String, now: Date = .now) -> Bool {
        seen = seen.filter { now.timeIntervalSince($0.value) < 600 }
        let hash = SHA256.hash(data: Data(text.precomposedStringWithCanonicalMapping.utf8)).map { String(format: "%02x", $0) }.joined()
        guard seen[hash] == nil else { return false }
        seen[hash] = now
        if seen.count > 50, let oldest = seen.min(by: { $0.value < $1.value })?.key { seen.removeValue(forKey: oldest) }
        return true
    }
}
