import Foundation
import Observation

@MainActor @Observable final class ManualAnalysisModel {
    var input = ""
    private(set) var result: FrenchAnalysis?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    private let service: LanguageAnalysisService
    private let history: HistoryStore
    private let settings: SettingsStore

    init(service: LanguageAnalysisService, history: HistoryStore, settings: SettingsStore) {
        self.service = service
        self.history = history
        self.settings = settings
    }

    func analyze() {
        guard !isLoading else { return }
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 4_000 else {
            errorMessage = AppError.invalidInput.errorDescription
            return
        }
        result = nil
        errorMessage = nil
        isLoading = true
        let id = UUID()
        requestID = id
        // Turning history off while a request is running must also prevent its storage.
        let historyWasEnabled = settings.saveHistory
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.requestID == id { self.isLoading = false; self.task = nil } }
            do {
                let analysis = try await self.service.analyze(query)
                try Task.checkCancellation()
                guard self.requestID == id else { return }
                self.result = analysis
                if historyWasEnabled && self.settings.saveHistory {
                    try self.history.record(analysis, source: .manual)
                }
            } catch is CancellationError {
                // Cancellation is an explicit action, not a failure.
            } catch {
                if self.requestID == id { self.errorMessage = AppError.message(for: error) }
            }
        }
    }

    func cancel() {
        requestID = UUID()
        task?.cancel()
        task = nil
        isLoading = false
    }
}
