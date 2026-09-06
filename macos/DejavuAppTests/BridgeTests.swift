import Foundation
import Network
import SwiftData
import XCTest
@testable import DejavuApp

@MainActor final class BridgeTests: XCTestCase {
    private let token = "example-local-pairing-code"
    private let extensionID = String(repeating: "a", count: 32)

    func testParserAcceptsFragmentsAndRejectsAmbiguousFraming() throws {
        let head = "POST /v1/analyze HTTP/1.1\r\nHost: 127.0.0.1:17389\r\nContent-Length: 2\r\n\r\n"
        XCTAssertNil(try BridgeHTTPParser.parse(Data(head.utf8)))
        XCTAssertEqual(try BridgeHTTPParser.parse(Data((head + "{}").utf8))?.body, Data("{}".utf8))
        for value in [
            head + "{}extra",
            "GET /v1/health HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n",
            "POST /v1/analyze HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n",
            "GET http://example.com HTTP/1.1\r\nHost: a\r\n\r\n",
            "GET /v1/health?token=placeholder HTTP/1.1\r\nHost: a\r\n\r\n",
            "POST /v1/analyze HTTP/1.1\r\nHost: a\r\nContent-Length: -1\r\n\r\n",
            "POST /v1/analyze HTTP/1.1\r\nHost: a\r\nContent-Length: 16385\r\n\r\n"
        ] { XCTAssertThrowsError(try BridgeHTTPParser.parse(Data(value.utf8))) }
        XCTAssertThrowsError(try BridgeHTTPParser.parse(Data(repeating: 65, count: 8_193)))
    }

    func testAllEndpointsRequireAuthenticationAndRejectWebOriginsAndRebinding() async throws {
        let h = try harness()
        for path in ["/v1/health", "/v1/analyze", "/v1/save"] {
            var headers = authHeaders
            headers.removeValue(forKey: "authorization")
            let response = await h.router.handle(request(path, headers: headers))
            XCTAssertEqual(response.status, 401)
        }
        var headers = authHeaders
        headers["host"] = "malicious.example:17389"
        let rejected1 = await awaitStatus(h.router, request("/v1/health", headers: headers))
        XCTAssertEqual(rejected1, 403)
        headers = authHeaders; headers["origin"] = "https://example.com"
        let rejected2 = await awaitStatus(h.router, request("/v1/health", headers: headers))
        XCTAssertEqual(rejected2, 403)
        headers["origin"] = "chrome-extension://" + String(repeating: "b", count: 32)
        let rejected3 = await awaitStatus(h.router, request("/v1/health", headers: headers))
        XCTAssertEqual(rejected3, 403)
        XCTAssertTrue(h.service.requests.isEmpty)
    }

    func testHealthAndCorsPreflightDoNotCallAI() async throws {
        let h = try harness()
        var headers = authHeaders
        headers["origin"] = "chrome-extension://" + extensionID
        let health = await h.router.handle(request("/v1/health", headers: headers))
        XCTAssertEqual(health.status, 200)
        XCTAssertEqual(health.headers["Access-Control-Allow-Origin"], headers["origin"])
        XCTAssertFalse(String(decoding: health.body, as: UTF8.self).contains(token))
        headers.removeValue(forKey: "authorization")
        headers["access-control-request-method"] = "POST"
        headers["access-control-request-headers"] = "authorization, content-type"
        let preflight = await h.router.handle(request("/v1/analyze", method: "OPTIONS", headers: headers))
        XCTAssertEqual(preflight.status, 204)
        headers["access-control-request-headers"] = "x-untrusted"
        let rejected = await h.router.handle(request("/v1/analyze", method: "OPTIONS", headers: headers))
        XCTAssertEqual(rejected.status, 403)
        XCTAssertTrue(h.service.requests.isEmpty)
    }

    func testAnalyzeAndSaveUseSharedVocabularyAndNeverStoreRawQuery() async throws {
        let h = try harness()
        let response = await h.router.handle(request("/v1/analyze", method: "POST", body: ["text": "Как мягко дать совет?"]))
        XCTAssertEqual(response.status, 200)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let id = try XCTUnwrap(json["id"] as? String)
        let result = await h.router.handle(request("/v1/save", method: "POST", body: ["id": id]))
        XCTAssertEqual(result.status, 200)
        _ = await h.router.handle(request("/v1/save", method: "POST", body: ["id": id]))
        let entry = try XCTUnwrap(h.vocabulary.find("tu devrais"))
        XCTAssertTrue(entry.savedByUser)
        XCTAssertEqual(entry.source, .chromePopup)
        XCTAssertEqual(entry.seenCount, 1)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<CommandPaletteHistoryEntry>()), 0)
        let invalid = await h.router.handle(request("/v1/save", method: "POST", body: ["id": UUID().uuidString]))
        XCTAssertEqual(invalid.status, 404)
        h.router.clearResults()
        let expired = await h.router.handle(request("/v1/save", method: "POST", body: ["id": id]))
        XCTAssertEqual(expired.status, 404)
    }

    func testBadJSONContentTypeAndProviderErrorsAreSafe() async throws {
        let h = try harness()
        let bad = await h.router.handle(request("/v1/analyze", method: "POST", body: ["wrong": "bonjour"]))
        XCTAssertEqual(bad.status, 400)
        let long = await h.router.handle(request("/v1/analyze", method: "POST", body: ["text": String(repeating: "a", count: 4_001)]))
        XCTAssertEqual(long.status, 400)
        var headers = authHeaders; headers["content-type"] = "text/plain"
        let plain = await h.router.handle(request("/v1/analyze", method: "POST", headers: headers))
        XCTAssertEqual(plain.status, 415)
        h.service.error = AppError.missingAPIKey
        let missingKey = await h.router.handle(request("/v1/analyze", method: "POST", body: ["text": "bonjour"]))
        XCTAssertEqual(missingKey.status, 503)
        XCTAssertFalse(String(decoding: missingKey.body, as: UTF8.self).contains(token))
        h.service.error = AppError.timedOut
        let timeout = await h.router.handle(request("/v1/analyze", method: "POST", body: ["text": "bonjour"]))
        XCTAssertEqual(timeout.status, 504)
    }

    func testStopAndHistoryChangesPreventLatePersistence() async throws {
        let h = try harness()
        h.service.suspend = true
        let request = request("/v1/analyze", method: "POST", body: ["text": "bonjour"])
        let work = Task { await h.router.handle(request) }
        await settle { h.service.continuation != nil }
        h.router.stop()
        h.service.finish()
        let response = await work.value
        XCTAssertEqual(response.status, 503)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<AnalysisHistoryEntry>()), 0)
    }

    func testPrivacyToggleWhileWaitingDoesNotSaveAndRateLimitBoundsAI() async throws {
        let h = try harness()
        h.service.suspend = true
        let req = request("/v1/analyze", method: "POST", body: ["text": "bonjour"])
        let work = Task { await h.router.handle(req) }
        await settle { h.service.continuation != nil }
        try h.settings.update(provider: .openAI, model: h.settings.model, saveHistory: false)
        try h.settings.update(provider: .openAI, model: h.settings.model, saveHistory: true)
        h.service.finish()
        let response = await work.value
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<AnalysisHistoryEntry>()), 0)
        h.service.suspend = false
        for _ in 0..<19 { _ = await h.router.handle(req) }
        let limited = await h.router.handle(req)
        XCTAssertEqual(limited.status, 429)
        XCTAssertEqual(h.service.requests.count, 20)
    }

    func testPairingTokensAreRandomPersistentAndRotatableWithoutProviderKey() throws {
        let h = try harness()
        let store = FakeTokenStore()
        let bridge = BrowserBridge(settings: h.settings, service: h.service, history: h.history, vocabulary: h.vocabulary, tokens: store)
        let first = try bridge.pairingCode()
        XCTAssertEqual(first.count, 64)
        XCTAssertEqual(try bridge.pairingCode(), first)
        try bridge.rotate()
        XCTAssertNotEqual(try bridge.pairingCode(), first)
        XCTAssertFalse(h.settings.bridgeEnabled)
        XCTAssertThrowsError(try h.settings.updateBridge(enabled: true, extensionID: "https://example.com"))
        XCTAssertFalse(h.settings.bridgeEnabled)
    }

    func testRealLoopbackHTTPAuthenticationAndStop() async throws {
        let h = try harness()
        let server = LocalHTTPServer()
        defer { server.stop() }
        var port: UInt16?
        var failed = false
        server.onState = { ready, value in
            if ready { port = value; h.router.port = value ?? 0 } else { failed = true }
        }
        try server.start(port: 0) { await h.router.handle($0) }
        await settle { port != nil || failed }
        let actualPort = try XCTUnwrap(port)
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(actualPort)/v1/health"))
        var request = URLRequest(url: url)
        let (_, unauthorized) = try await session.data(for: request)
        XCTAssertEqual((unauthorized as? HTTPURLResponse)?.statusCode, 401)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertFalse(data.isEmpty)
        XCTAssertTrue(h.service.requests.isEmpty)
        request.url = URL(string: "http://127.0.0.1:\(actualPort)/v1/analyze")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["text": "bonjour"])
        let (analysisData, analyzed) = try await session.data(for: request)
        XCTAssertEqual((analyzed as? HTTPURLResponse)?.statusCode, 200)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: analysisData) as? [String: Any])
        let id = try XCTUnwrap(json["id"] as? String)
        request.url = URL(string: "http://127.0.0.1:\(actualPort)/v1/save")
        request.httpBody = try JSONEncoder().encode(["id": id])
        let (_, saved) = try await session.data(for: request)
        XCTAssertEqual((saved as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(try XCTUnwrap(h.vocabulary.find("tu devrais")).savedByUser)
        server.stop()
        do { _ = try await session.data(for: request); XCTFail("Stopped listener accepted a request") }
        catch { /* The socket must stop accepting connections. */ }
    }

    func testPairingKeychainAccountDoesNotReplaceProviderCredential() throws {
        let service = "com.dejavu.tests.bridge." + UUID().uuidString
        let provider = KeychainService(service: service)
        let pairing = KeychainService(service: service, account: "pairing-token")
        defer { try? provider.delete(); try? pairing.delete() }
        try provider.save("example-provider-key")
        try pairing.save("example-pairing-code")
        XCTAssertEqual(try provider.load(), "example-provider-key")
        XCTAssertEqual(try pairing.load(), "example-pairing-code")
        try pairing.delete()
        XCTAssertEqual(try provider.load(), "example-provider-key")
    }

    func testClearResultsWhileWaitingInvalidatesLateAnalysis() async throws {
        let h = try harness()
        h.service.suspend = true
        let req = request("/v1/analyze", method: "POST", body: ["text": "bonjour"])
        let work = Task { await h.router.handle(req) }
        await settle { h.service.continuation != nil }
        h.router.clearResults()
        h.service.finish()
        let response = await work.value
        XCTAssertEqual(response.status, 503)
        XCTAssertEqual(try h.container.mainContext.fetchCount(FetchDescriptor<AnalysisHistoryEntry>()), 0)
    }

    private var authHeaders: [String: String] {
        ["host": "127.0.0.1:17389", "authorization": "Bearer " + token, "content-type": "application/json"]
    }
    private func request(_ path: String, method: String = "GET", headers: [String: String]? = nil, body: [String: String] = [:]) -> BridgeRequest {
        .init(method: method, path: path, headers: headers ?? authHeaders, body: (try? JSONEncoder().encode(body)) ?? Data())
    }
    private func harness() throws -> BridgeHarness { try BridgeHarness(token: token, extensionID: extensionID) }
    private func awaitStatus(_ router: BridgeRouter, _ request: BridgeRequest) async -> Int { await router.handle(request).status }
    private func settle(_ predicate: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(4)
        while !predicate(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(predicate())
    }
}

@MainActor private struct BridgeHarness {
    let container: ModelContainer
    let settings: SettingsStore
    let vocabulary: VocabularyStore
    let history: HistoryStore
    let service = BridgeTestService()
    let router: BridgeRouter
    init(token: String, extensionID: String) throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        settings = try SettingsStore(context: container.mainContext)
        vocabulary = VocabularyStore(context: container.mainContext)
        history = HistoryStore(context: container.mainContext, vocabulary: vocabulary)
        router = BridgeRouter(token: token, extensionID: extensionID, port: 17389, service: service,
                              history: history, vocabulary: vocabulary, settings: settings)
    }
}

@MainActor private final class FakeTokenStore: APIKeyStore {
    var value: String?
    func load() throws -> String? { value }
    func save(_ key: String) throws { value = key }
    func delete() throws { value = nil }
}

@MainActor private final class BridgeTestService: LanguageAnalyzing {
    var requests: [AnalysisRequest] = []
    var error: AppError?
    var suspend = false
    var continuation: CheckedContinuation<AnalysisOutcome, Error>?
    func analyze(_ request: AnalysisRequest, forceRefresh: Bool) async throws -> AnalysisOutcome {
        requests.append(request)
        if let error { throw error }
        if suspend { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return AnalysisOutcome(analysis: PersistenceTests.analysis(), fromCache: false)
    }
    func finish() {
        continuation?.resume(returning: AnalysisOutcome(analysis: PersistenceTests.analysis(), fromCache: false))
        continuation = nil
    }
}
