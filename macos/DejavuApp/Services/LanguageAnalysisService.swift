import Foundation

@MainActor final class LanguageAnalysisService: LanguageAnalyzing {
    private let settings: SettingsStore
    private let keychain: any APIKeyStore
    private let cache: AnalysisCache
    private let providerFactory: ((AIProvider, String) throws -> any LanguageModelProvider)?

    init(settings: SettingsStore, keychain: any APIKeyStore, cache: AnalysisCache = AnalysisCache(),
         providerFactory: ((AIProvider, String) throws -> any LanguageModelProvider)? = nil) {
        self.settings = settings
        self.keychain = keychain
        self.cache = cache
        self.providerFactory = providerFactory
    }

    func analyze(_ input: String) async throws -> FrenchAnalysis {
        try await analyze(AnalysisRequest(query: input), forceRefresh: false).analysis
    }

    func analyze(_ request: AnalysisRequest, forceRefresh: Bool = false) async throws -> AnalysisOutcome {
        let request = try request.validated()
        try Task.checkCancellation()
        let key = AnalysisCache.Key(provider: settings.provider.rawValue, model: settings.model,
                                    requestFingerprint: try request.fingerprint())
        if !forceRefresh, let analysis = cache.value(for: key) {
            return AnalysisOutcome(analysis: analysis, fromCache: true)
        }
        let generation = cache.generation
        let analysis = try await provider().analyze(request).validated()
        try Task.checkCancellation()
        if generation == cache.generation { cache.insert(analysis, for: key) }
        return AnalysisOutcome(analysis: analysis, fromCache: false)
    }

    func clearCache() { cache.clear() }

    func testConnection() async throws {
        try await provider().testConnection()
    }

    private func provider() throws -> any LanguageModelProvider {
        if let providerFactory { return try providerFactory(settings.provider, settings.model) }
        guard let key = try keychain.load(), !key.isEmpty else { throw AppError.missingAPIKey }
        switch settings.provider {
        case .openAI:
            return OpenAIProvider(apiKey: key, model: settings.model, schema: try OpenAIProvider.bundledSchema())
        }
    }
}
