import Foundation
import Observation
import SwiftData

enum AppSection: String, CaseIterable, Identifiable {
    case home, saved, history, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Главная"
        case .saved: "Сохранённое"
        case .history: "История"
        case .settings: "Настройки"
        }
    }
    var symbol: String {
        switch self {
        case .home: "house"
        case .saved: "bookmark"
        case .history: "clock.arrow.circlepath"
        case .settings: "slider.horizontal.3"
        }
    }
}

@MainActor @Observable final class AppEnvironment {
    let container: ModelContainer
    let vocabulary: VocabularyStore
    let history: HistoryStore
    let settings: SettingsStore
    let keychain: KeychainService
    let analysisService: LanguageAnalysisService
    let manualAnalysis: ManualAnalysisModel
    let speech: SpeechService
    let commandPaletteModel: CommandPaletteModel
    let clipboardModel: ClipboardModel
    @ObservationIgnored lazy var clipboardMonitor = ClipboardMonitor()
    @ObservationIgnored lazy var clipboardPanel = ClipboardPanelController(app: self)
    private var integrationStarted = false
    private let inMemory: Bool
    @ObservationIgnored lazy var commandPalette = CommandPaletteController(app: self)
    @ObservationIgnored var openSettingsWindow: (() -> Void)?
    var clipboardSettingsError: String?
    var section: AppSection? = .home

    init(inMemory: Bool = false) throws {
        self.inMemory = inMemory
        container = try PersistenceController.makeContainer(inMemory: inMemory)
        vocabulary = VocabularyStore(context: container.mainContext)
        history = HistoryStore(context: container.mainContext, vocabulary: vocabulary)
        settings = try SettingsStore(context: container.mainContext)
        keychain = KeychainService()
        analysisService = LanguageAnalysisService(settings: settings, keychain: keychain)
        manualAnalysis = ManualAnalysisModel(service: analysisService, history: history, settings: settings)
        speech = SpeechService()
        commandPaletteModel = CommandPaletteModel(service: analysisService, vocabulary: vocabulary, history: history,
                                                  queryHistory: CommandPaletteHistoryStore(context: container.mainContext),
                                                  settings: settings, speech: speech)
        clipboardModel = ClipboardModel(service: analysisService, settings: settings, history: history)
    }

    func configureClipboard() {
        guard !inMemory else { return }
        clipboardMonitor.stop()
        clipboardModel.clear()
        clipboardModel.onUpdate = { [weak self] in self?.clipboardPanel.update() }
        clipboardMonitor.onChange = { [weak self] in self?.clipboardModel.clear() }
        clipboardMonitor.onCandidate = { [weak self] text in self?.clipboardModel.receive(text) }
        if settings.clipboardEnabled { clipboardMonitor.start() }
    }

    func setClipboard(enabled: Bool? = nil, automatic: Bool? = nil, showPanel: Bool? = nil, history: Bool? = nil) throws {
        // Stop immediately, including if saving the new preference fails.
        clipboardMonitor.stop()
        clipboardModel.clear()
        clipboardSettingsError = nil
        do {
            try settings.updateClipboard(enabled: enabled ?? settings.clipboardEnabled,
                                     automatic: automatic ?? settings.clipboardAutomatic,
                                     showPanel: showPanel ?? settings.clipboardShowPanel,
                                     history: history ?? settings.clipboardHistory)
            configureClipboard()
        } catch {
            clipboardSettingsError = "Проверка буфера остановлена: не удалось сохранить настройки. Повторите изменение настроек."
            throw error
        }
    }

    func startSystemIntegration() {
        guard !inMemory, !integrationStarted else { return }
        integrationStarted = true
        commandPalette.start()
        configureClipboard()
    }

    func clearHistory() throws {
        try history.clear()
        clipboardModel.clear()
        manualAnalysis.cancel()
        commandPaletteModel.clear()
        analysisService.clearCache()
    }
}

@MainActor @Observable final class AppBootstrap {
    var environment: AppEnvironment?
    var failed = false

    init() { start() }

    func start() {
        do {
            // Hosted tests must never modify the user's persistent database.
            environment = try AppEnvironment(inMemory: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
            failed = false
        } catch {
            failed = true
        }
    }
}
