import Foundation
import Observation

@MainActor @Observable final class DialogueModel {
    private let service: any DialogueServing
    private let vocabulary: VocabularyStore
    private let settings: SettingsStore
    private var task: Task<Void, Never>?
    private var revision = UUID()
    private(set) var isOpen = false
    private(set) var isLoading = false
    private(set) var scenario: DialogueScenario?
    private(set) var feedback: DialogueFeedback?
    private(set) var saved = false
    private(set) var recentQuestions: [String] = []
    private(set) var contextIndex = 0
    var answer = ""
    var errorMessage: String?
    @ObservationIgnored var onUpdate: (() -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    static let contexts = ["друг: планы", "кафе", "коллега", "вокзал", "магазин", "сосед", "отель", "аэропорт",
                           "арендодатель", "регистратура врача", "французская администрация", "светская беседа",
                           "совместные планы", "просьба о помощи", "своё мнение"]

    init(service: any DialogueServing, vocabulary: VocabularyStore, settings: SettingsStore) {
        self.service = service; self.vocabulary = vocabulary; self.settings = settings
    }
    func start() {
        guard !isOpen else { return }
        isOpen = true; isLoading = true; errorMessage = nil; answer = ""; feedback = nil; scenario = nil; saved = false
        let token = UUID(); revision = token
        let index = contextIndex
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let words = settings.dialogueReuseVocabulary ? try vocabulary.dialogueVocabulary() : []
                let value = try await service.scenario(context: Self.contexts[index % Self.contexts.count],
                    recent: recentQuestions, vocabulary: words, stretch: index % 5 == 4).validated()
                guard revision == token, !Task.isCancelled else { return }
                guard !recentQuestions.contains(where: { ExpressionNormalizer.normalize($0) == ExpressionNormalizer.normalize(value.question) }) else {
                    throw AppError.invalidResponse
                }
                scenario = value
                contextIndex += 1
                recentQuestions = Array((recentQuestions + [value.question]).suffix(20))
            } catch {
                guard revision == token, !Task.isCancelled else { return }
                errorMessage = AppError.message(for: error)
            }
            isLoading = false; onUpdate?()
        }
        onUpdate?()
    }
    func submit() {
        guard let scenario, !isLoading, feedback == nil else { return }
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2000 else { errorMessage = "Напишите ответ до 2 000 символов."; return }
        let token = revision
        isLoading = true; errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.feedback(scenario: scenario, answer: text).validated()
                guard revision == token, !Task.isCancelled else { return }
                feedback = result
            } catch {
                guard revision == token, !Task.isCancelled else { return }
                errorMessage = AppError.message(for: error)
            }
            isLoading = false; onUpdate?()
        }
        onUpdate?()
    }
    func savePhrase() {
        guard let feedback, !saved else { return }
        do { try vocabulary.save(feedback.phraseAnalysis, source: .conversationGhost); saved = true; errorMessage = nil }
        catch { errorMessage = AppError.message(for: error) }
    }
    func close() {
        revision = UUID(); task?.cancel(); task = nil
        isOpen = false; isLoading = false; scenario = nil; feedback = nil; answer = ""; errorMessage = nil; saved = false
        onClose?(); onUpdate?()
    }
    func clearMemory() { close(); recentQuestions = []; contextIndex = 0 }
}

struct DialogueTiming {
    static func next(now: Date, minutes: Int, jitter: Double) -> Date {
        now.addingTimeInterval(Double(minutes) * 60 * (1 + min(0.2, max(0, jitter))))
    }
    static func shouldTrigger(now: Date, due: Date, pausedUntil: Date?, enabled: Bool,
                              isOpen: Bool, safe: Bool, idleSeconds: Double) -> Bool {
        enabled && !isOpen && safe && now >= due && (pausedUntil == nil || now >= pausedUntil!) &&
        idleSeconds >= 4 && idleSeconds <= 120
    }
    static func tomorrow(now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
    }
}
