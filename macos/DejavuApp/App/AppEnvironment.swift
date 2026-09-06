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
    var section: AppSection? = .home

    init(inMemory: Bool = false) throws {
        container = try PersistenceController.makeContainer(inMemory: inMemory)
        vocabulary = VocabularyStore(context: container.mainContext)
        history = HistoryStore(context: container.mainContext, vocabulary: vocabulary)
        settings = try SettingsStore(context: container.mainContext)
        keychain = KeychainService()
        analysisService = LanguageAnalysisService(settings: settings, keychain: keychain)
        manualAnalysis = ManualAnalysisModel(service: analysisService, history: history, settings: settings)
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
