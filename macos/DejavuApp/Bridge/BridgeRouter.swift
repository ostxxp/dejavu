import Foundation

@MainActor final class BridgeRouter {
    private let token: String
    private let extensionID: String
    var port: UInt16
    private let service: any LanguageAnalyzing
    private let history: HistoryStore
    private let vocabulary: VocabularyStore
    private let settings: SettingsStore
    private let now: () -> Date
    private var active = true
    private var generation = 0
    private var analyzing = 0
    private var requests: [Date] = []
    private var issued: [UUID: (FrenchAnalysis, Date)] = [:]

    init(token: String, extensionID: String, port: UInt16, service: any LanguageAnalyzing,
         history: HistoryStore, vocabulary: VocabularyStore, settings: SettingsStore, now: @escaping () -> Date = Date.init) {
        self.token = token; self.extensionID = extensionID; self.port = port
        self.service = service; self.history = history; self.vocabulary = vocabulary; self.settings = settings; self.now = now
    }

    func stop() { active = false; clearResults() }
    func clearResults() { generation += 1; issued.removeAll() }

    func handle(_ request: BridgeRequest) async -> BridgeResponse {
        guard active else { return .error(503, "disabled", "Подключение выключено.") }
        guard request.headers["host"] == "127.0.0.1:\(port)" else { return .error(403, "invalid_host", "Недопустимый адрес подключения.") }
        let origin = request.headers["origin"]
        if let origin, extensionID.isEmpty || origin != "chrome-extension://\(extensionID)" {
            return .error(403, "invalid_origin", "Это расширение не подключено.")
        }
        var response: BridgeResponse
        if request.method == "OPTIONS" {
            guard origin != nil, ["GET", "POST"].contains(request.headers["access-control-request-method"] ?? ""),
                  request.headers["access-control-request-headers"]?.lowercased().split(separator: ",").allSatisfy({
                      ["authorization", "content-type"].contains($0.trimmingCharacters(in: .whitespaces))
                  }) != false else { return .error(403, "invalid_preflight", "Запрос подключения отклонён.") }
            response = .init(status: 204, body: Data())
            response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
            response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
            if request.headers["access-control-request-private-network"] == "true" {
                response.headers["Access-Control-Allow-Private-Network"] = "true"
            }
        } else {
            if Self.matches(request.headers["authorization"] ?? "", "Bearer " + token) {
                response = await route(request)
            } else {
                response = .error(401, "unauthorized", "Нужен действующий код подключения.")
            }
        }
        if let origin {
            response.headers["Access-Control-Allow-Origin"] = origin
            response.headers["Vary"] = "Origin"
        }
        return response
    }

    private func route(_ request: BridgeRequest) async -> BridgeResponse {
        if request.path == "/v1/health", request.method == "GET" {
            return .json(["status": "ok", "version": "1", "appVersion": "0.4.0"])
        }
        guard ["/v1/analyze", "/v1/save"].contains(request.path) else { return .error(404, "not_found", "Такого действия нет.") }
        guard request.method == "POST" else { return .error(405, "method_not_allowed", "Используйте POST.") }
        guard request.headers["content-type"]?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else {
            return .error(415, "json_required", "Ожидается JSON.")
        }
        do {
            try Task.checkCancellation()
            if request.path == "/v1/save" {
                struct Input: Decodable { let id: UUID }
                let input = try JSONDecoder().decode(Input.self, from: request.body)
                purge()
                guard let (analysis, _) = issued[input.id] else { return .error(404, "analysis_expired", "Разбор устарел. Получите его заново.") }
                _ = try vocabulary.save(analysis, source: .chromePopup)
                return .json(["saved": true])
            }
            struct Input: Decodable { let text: String }
            let input = try JSONDecoder().decode(Input.self, from: request.body)
            let query = try AnalysisRequest(query: input.text).validated()
            let current = now()
            requests.removeAll { current.timeIntervalSince($0) >= 60 }
            guard analyzing < 2, requests.count < 20 else { return .error(429, "busy", "Слишком много запросов. Попробуйте позже.") }
            analyzing += 1; requests.append(current)
            defer { analyzing -= 1 }
            let generation = self.generation
            let save = settings.saveHistory
            let revision = settings.historyRevision
            let outcome = try await service.analyze(query, forceRefresh: false)
            try Task.checkCancellation()
            guard active, self.generation == generation else { return .error(503, "disabled", "Подключение выключено или история очищена.") }
            if save && settings.saveHistory && revision == settings.historyRevision {
                try history.record(outcome.analysis, source: .chromePopup)
            }
            purge()
            let id = UUID()
            issued[id] = (outcome.analysis, now())
            if issued.count > 100, let oldest = issued.min(by: { $0.value.1 < $1.value.1 })?.key { issued.removeValue(forKey: oldest) }
            struct Output: Encodable { let id: UUID; let analysis: FrenchAnalysis; let fromCache: Bool }
            return .json(Output(id: id, analysis: outcome.analysis, fromCache: outcome.fromCache))
        } catch is DecodingError {
            return .error(400, "invalid_json", "Проверьте поля запроса.")
        } catch is CancellationError {
            return .error(503, "cancelled", "Запрос отменён.")
        } catch let error as AppError {
            let status: Int
            switch error {
            case .invalidInput: status = 400
            case .rateLimited: status = 429
            case .timedOut: status = 504
            case .missingAPIKey, .invalidModel, .keychain, .unauthorized: status = 503
            case .storage: status = 500
            default: status = 502
            }
            return .error(status, "analysis_failed", AppError.message(for: error))
        } catch { return .error(500, "internal_error", "Не удалось выполнить действие.") }
    }

    private func purge() { let date = now(); issued = issued.filter { date.timeIntervalSince($0.value.1) < 1_800 } }

    private static func matches(_ supplied: String, _ expected: String) -> Bool {
        let a = Array(supplied.utf8), b = Array(expected.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
