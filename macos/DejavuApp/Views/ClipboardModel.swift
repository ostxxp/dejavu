import Foundation
import Observation

@MainActor @Observable final class ClipboardModel {
    private(set) var candidate: String?
    private(set) var result: FrenchAnalysis?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var fromCache = false
    var showsDetails = false
    @ObservationIgnored var onUpdate: (() -> Void)?
    private let service: any LanguageAnalyzing
    private let settings: SettingsStore
    private let history: HistoryStore
    private var task: Task<Void, Never>?
    private var requestID = UUID()

    init(service: any LanguageAnalyzing, settings: SettingsStore, history: HistoryStore) {
        self.service = service
        self.settings = settings
        self.history = history
    }

    var hasContent: Bool { candidate != nil || result != nil || errorMessage != nil }

    func receive(_ text: String) {
        clear()
        guard settings.clipboardEnabled else { return }
        candidate = text
        if settings.clipboardAutomatic && text.count <= 500 { analyze() }
        else { onUpdate?() }
    }

    func analyze() {
        guard settings.clipboardEnabled, !isLoading, let text = candidate else { return }
        isLoading = true
        errorMessage = nil
        let id = UUID()
        requestID = id
        let revision = settings.historyRevision
        let clipboardRevision = settings.clipboardRevision
        let save = settings.saveHistory && settings.clipboardHistory
        onUpdate?()
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.requestID == id { self.isLoading = false; self.task = nil; self.onUpdate?() } }
            do {
                let outcome = try await self.service.analyze(AnalysisRequest(query: text), forceRefresh: false)
                try Task.checkCancellation()
                guard self.requestID == id, self.settings.clipboardEnabled,
                      clipboardRevision == self.settings.clipboardRevision else { return }
                self.result = outcome.analysis
                self.fromCache = outcome.fromCache
                self.candidate = nil
                if save && self.settings.saveHistory && self.settings.clipboardHistory && revision == self.settings.historyRevision {
                    try self.history.record(outcome.analysis, source: .clipboard)
                }
            } catch is CancellationError {
            } catch { if self.requestID == id { self.errorMessage = AppError.message(for: error) } }
        }
    }

    func clear() {
        requestID = UUID()
        task?.cancel()
        task = nil
        candidate = nil
        result = nil
        isLoading = false
        errorMessage = nil
        fromCache = false
        showsDetails = false
        onUpdate?()
    }
}
