import Foundation

@MainActor final class LanguageAnalysisService {
    private let settings: SettingsStore
    private let keychain: any APIKeyStore

    init(settings: SettingsStore, keychain: any APIKeyStore) {
        self.settings = settings
        self.keychain = keychain
    }

    func analyze(_ input: String) async throws -> FrenchAnalysis {
        try await provider().analyze(input)
    }

    func testConnection() async throws {
        try await provider().testConnection()
    }

    private func provider() throws -> any LanguageModelProvider {
        guard let key = try keychain.load(), !key.isEmpty else { throw AppError.missingAPIKey }
        switch settings.provider {
        case .openAI:
            return OpenAIProvider(apiKey: key, model: settings.model, schema: try OpenAIProvider.bundledSchema())
        }
    }
}
