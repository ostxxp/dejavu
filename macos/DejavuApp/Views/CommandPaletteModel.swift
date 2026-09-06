import Foundation
import Observation

/// Recency navigation preserves the draft when moving back past the newest request.
struct QueryHistoryCursor {
    var requests: [AnalysisRequest] = []
    private var index: Int?
    private var draft: AnalysisRequest?

    mutating func reset(_ requests: [AnalysisRequest]) {
        self.requests = requests
        index = nil
        draft = nil
    }

    mutating func previous(from current: AnalysisRequest) -> AnalysisRequest? {
        guard !requests.isEmpty else { return nil }
        if index == nil { draft = current }
        index = min((index ?? -1) + 1, requests.count - 1)
        return requests[index!]
    }

    mutating func next() -> AnalysisRequest? {
        guard let current = index else { return nil }
        if current > 0 {
            index = current - 1
            return requests[current - 1]
        }
        index = nil
        defer { draft = nil }
        return draft
    }
}

@MainActor @Observable final class CommandPaletteModel {
    var input = ""
    private(set) var result: FrenchAnalysis?
    private(set) var fromCache = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var notice: String?
    private(set) var context: FollowUpContext?
    private(set) var completedFollowUp = false
    private(set) var lastRequest: AnalysisRequest?
    private(set) var focusToken = 0
    var showsDetails = false

    private let service: any LanguageAnalyzing
    private let vocabulary: VocabularyStore
    private let history: HistoryStore
    private let queryHistory: CommandPaletteHistoryStore
    private let settings: SettingsStore
    private let speech: any FrenchSpeaking
    private var cursor = QueryHistoryCursor()
    private var task: Task<Void, Never>?
    private var requestID = UUID()

    init(service: any LanguageAnalyzing, vocabulary: VocabularyStore, history: HistoryStore,
         queryHistory: CommandPaletteHistoryStore, settings: SettingsStore, speech: any FrenchSpeaking) {
        self.service = service
        self.vocabulary = vocabulary
        self.history = history
        self.queryHistory = queryHistory
        self.settings = settings
        self.speech = speech
    }

    var canSubmit: Bool {
        !isLoading && !completedFollowUp && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && input.count <= 4_000
    }

    var canFollowUp: Bool { result != nil && lastRequest?.context == nil && context == nil && !isLoading }
    var preferredHeight: Double {
        if result != nil { return showsDetails ? 720 : 610 }
        return errorMessage == nil ? 235 : 320
    }

    func prepareToShow() {
        reloadHistory()
        focusToken += 1
    }

    func submit(forceRefresh: Bool = false) {
        guard canSubmit else { return }
        start(AnalysisRequest(query: input, context: context), forceRefresh: forceRefresh)
    }

    func refresh() {
        guard !isLoading, let lastRequest else { return }
        input = lastRequest.query
        context = lastRequest.context
        start(lastRequest, forceRefresh: true)
    }

    private func start(_ proposedRequest: AnalysisRequest, forceRefresh: Bool) {
        guard !isLoading else { return }
        let request: AnalysisRequest
        do { request = try proposedRequest.validated() }
        catch { errorMessage = AppError.message(for: error); return }
        speech.stop()
        errorMessage = nil
        notice = nil
        completedFollowUp = false
        if request.context == nil { result = nil; showsDetails = false }
        isLoading = true
        let id = UUID()
        requestID = id
        let saveHistory = settings.saveHistory
        let historyRevision = settings.historyRevision
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.requestID == id {
                    self.isLoading = false
                    self.task = nil
                    if !self.completedFollowUp { self.focusToken += 1 }
                }
            }
            do {
                let outcome = try await self.service.analyze(request, forceRefresh: forceRefresh)
                try Task.checkCancellation()
                guard self.requestID == id else { return }
                self.result = outcome.analysis
                self.fromCache = outcome.fromCache
                self.lastRequest = request
                self.completedFollowUp = request.context != nil
                if saveHistory && self.settings.saveHistory && historyRevision == self.settings.historyRevision {
                    try self.history.record(outcome.analysis, source: .commandPalette, request: request)
                    self.reloadHistory()
                }
            } catch is CancellationError {
                // Closing/clearing must not display errors or persist late responses.
            } catch {
                if self.requestID == id { self.errorMessage = AppError.message(for: error) }
            }
        }
    }

    func beginFollowUp() {
        guard canFollowUp, let result, let lastRequest else { return }
        context = FollowUpContext(originalQuery: lastRequest.query, analysis: result)
        input = ""
        errorMessage = nil
        notice = nil
        focusToken += 1
    }

    func save() {
        guard !isLoading, let result else { return }
        do {
            _ = try vocabulary.save(result, source: .commandPalette)
            notice = "Выражение сохранено"
            errorMessage = nil
        } catch { errorMessage = AppError.message(for: error) }
    }

    func listen() {
        guard !isLoading, let result else { return }
        do { try speech.speak(result.original); errorMessage = nil }
        catch { errorMessage = AppError.message(for: error) }
    }

    func previousQuery() {
        guard !isLoading else { return }
        if let request = cursor.previous(from: AnalysisRequest(query: input, context: context)) { restore(request) }
    }

    func nextQuery() {
        guard !isLoading else { return }
        if let request = cursor.next() { restore(request) }
    }

    private func restore(_ request: AnalysisRequest) {
        input = request.query
        context = request.context
        result = request.context?.analysis
        lastRequest = nil
        completedFollowUp = false
        fromCache = false
        errorMessage = nil
        notice = nil
        showsDetails = false
    }

    func cancel() {
        requestID = UUID()
        task?.cancel()
        task = nil
        isLoading = false
        speech.stop()
        focusToken += 1
    }

    func clear() {
        cancel()
        input = ""
        result = nil
        context = nil
        lastRequest = nil
        completedFollowUp = false
        fromCache = false
        showsDetails = false
        errorMessage = nil
        notice = nil
        reloadHistory()
        focusToken += 1
    }

    private func reloadHistory() {
        do { cursor.reset(try queryHistory.recentRequests()) }
        catch { errorMessage = AppError.storage.errorDescription }
    }
}
