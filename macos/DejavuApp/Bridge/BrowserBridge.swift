import Foundation
import Observation
import Security

@MainActor @Observable final class BrowserBridge {
    static let port: UInt16 = 17389
    private(set) var status = "Выключено"
    private(set) var isRunning = false
    private(set) var errorMessage: String?
    private let settings: SettingsStore
    private let tokens: any APIKeyStore
    private let service: any LanguageAnalyzing
    private let history: HistoryStore
    private let vocabulary: VocabularyStore
    @ObservationIgnored private let server = LocalHTTPServer()
    @ObservationIgnored private var router: BridgeRouter?

    init(settings: SettingsStore, service: any LanguageAnalyzing, history: HistoryStore, vocabulary: VocabularyStore,
         tokens: any APIKeyStore = KeychainService(service: "com.dejavu.mac.browser-bridge", account: "pairing-token")) {
        self.settings = settings; self.service = service; self.history = history; self.vocabulary = vocabulary; self.tokens = tokens
    }

    static func makeToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AppError.keychain }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func startIfEnabled() {
        guard settings.bridgeEnabled else { return }
        do { try start() } catch { fail(error) }
    }

    func configure(enabled: Bool, extensionID: String) {
        stop()
        do {
            try settings.updateBridge(enabled: enabled, extensionID: extensionID)
            if enabled { try start() }
        } catch { fail(error) }
    }

    func pairingCode() throws -> String {
        if let existing = try tokens.load() {
            guard existing.utf8.count == 64, existing.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw AppError.keychain }
            return existing
        }
        let token = try Self.makeToken()
        try tokens.save(token)
        return token
    }

    func rotate() throws {
        stop()
        try tokens.save(Self.makeToken())
        if settings.bridgeEnabled { try start() }
    }

    func stop() {
        router?.stop(); router = nil
        server.stop()
        isRunning = false
        status = "Выключено"
        errorMessage = nil
    }

    func clearResults() { router?.clearResults() }

    private func start() throws {
        stop()
        let router = BridgeRouter(token: try pairingCode(), extensionID: settings.bridgeExtensionID, port: Self.port,
                                  service: service, history: history, vocabulary: vocabulary, settings: settings)
        self.router = router
        status = "Подключаем…"
        server.onState = { [weak self, weak router] ready, _ in
            guard let self, let router, self.router === router else { return }
            self.isRunning = ready
            self.status = ready ? "Готово к подключению" : "Не удалось запустить"
            if !ready {
                router.stop()
                self.errorMessage = "Порт 17389 недоступен. Закройте другую копию DéjàVu или приложение, которое использует этот порт, и повторите подключение."
            }
        }
        try server.start(port: Self.port) { [weak router] request in
            guard let router else { return .error(503, "disabled", "Подключение выключено.") }
            return await router.handle(request)
        }
    }

    private func fail(_ error: Error) {
        stop()
        status = "Не удалось подключить"
        errorMessage = AppError.message(for: error)
    }
}
