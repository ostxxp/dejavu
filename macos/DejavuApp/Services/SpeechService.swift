import AVFoundation
import Foundation
import Observation

@MainActor protocol FrenchSpeaking {
    func speak(_ text: String) throws
    func stop()
}

@MainActor @Observable final class SpeechService: NSObject, FrenchSpeaking, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4_000 else { throw AppError.invalidInput }
        guard let voice = AVSpeechSynthesisVoice(language: "fr-FR"), voice.language == "fr-FR" else {
            throw AppError.missingFrenchVoice
        }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.synchronizeState() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.synchronizeState() }
    }

    private func synchronizeState() { isSpeaking = synthesizer.isSpeaking }
}
