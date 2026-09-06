import XCTest
@testable import DejavuApp

@MainActor final class OpenAIProviderTests: XCTestCase {
    func testStructuredResponseAndPrivacyRequest() async throws {
        let analysis = PersistenceTests.analysis()
        let encoded = String(decoding: try JSONEncoder().encode(analysis), as: UTF8.self)
        let data = try envelope(output: [
            ["type": "reasoning"],
            ["type": "message", "content": [["type": "output_text", "text": encoded]]]
        ])
        let transport = StubTransport(data: data)
        let provider = try makeProvider(transport)
        let result = try await provider.analyze("tu devrais")
        XCTAssertEqual(result, analysis)
        let capturedRequest = await transport.lastRequest
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer placeholder")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["input"] as? String, "tu devrais")
        XCTAssertNil(body["apiKey"])
        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
        try checkSchema(try XCTUnwrap(format["schema"] as? [String: Any]))
    }

    func testConnectionUsesSameStructuredPath() async throws {
        let encoded = String(decoding: try JSONEncoder().encode(PersistenceTests.analysis("bonjour")), as: UTF8.self)
        let transport = StubTransport(data: try envelope(output: [["type": "message", "content": [["type": "output_text", "text": encoded]]]]))
        try await makeProvider(transport).testConnection()
        let capturedRequest = await transport.lastRequest
        let request = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["input"] as? String, "bonjour")
    }

    func testRefusalIncompleteAndMalformedResponses() async throws {
        let cases: [(Data, AppError)] = [
            (try envelope(output: [["type": "message", "content": [["type": "refusal", "refusal": "private server text"]]]]), .refused),
            (try envelope(status: "incomplete", output: []), .incompleteResponse),
            (Data("not JSON".utf8), .invalidResponse),
            (try envelope(output: []), .invalidResponse)
        ]
        for (data, expected) in cases {
            do { _ = try await makeProvider(StubTransport(data: data)).analyze("bonjour"); XCTFail("Expected failure") }
            catch { XCTAssertEqual(error as? AppError, expected) }
        }
    }

    func testHTTPFailuresDoNotExposeServerBody() async throws {
        for (status, expected) in [(401, AppError.unauthorized), (403, .unauthorized), (429, .rateLimited),
                                   (500, .unavailable), (302, .unavailable), (400, .invalidModel)] {
            do {
                _ = try await makeProvider(StubTransport(data: Data("private server text".utf8), status: status)).analyze("bonjour")
                XCTFail("Expected failure")
            } catch {
                XCTAssertEqual(error as? AppError, expected)
                XCTAssertFalse(AppError.message(for: error).contains("private server text"))
            }
        }
    }

    func testEmptyAndLongInputNeverReachTransport() async throws {
        let transport = StubTransport(data: Data())
        let provider = try makeProvider(transport)
        for input in [" \n", String(repeating: "a", count: 4_001)] {
            do { _ = try await provider.analyze(input); XCTFail("Expected failure") }
            catch { XCTAssertEqual(error as? AppError, .invalidInput) }
        }
        let request = await transport.lastRequest
        XCTAssertNil(request)
    }

    func testTransportTimeoutAndCancellation() async throws {
        do { _ = try await makeProvider(FailingTransport(code: .timedOut)).analyze("bonjour"); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? AppError, .timedOut) }
        do { _ = try await makeProvider(FailingTransport(code: .cancelled)).analyze("bonjour"); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func makeProvider(_ transport: any HTTPTransport) throws -> OpenAIProvider {
        OpenAIProvider(apiKey: "placeholder", model: "gpt-4o-mini", schema: try OpenAIProvider.bundledSchema(), transport: transport)
    }

    private func envelope(status: String = "completed", output: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["status": status, "output": output])
    }

    private func checkSchema(_ schema: [String: Any]) throws {
        if schema["type"] as? String == "object" {
            let properties = try XCTUnwrap(schema["properties"] as? [String: [String: Any]])
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
            XCTAssertEqual(Set(schema["required"] as? [String] ?? []), Set(properties.keys))
            for value in properties.values { try checkSchema(value) }
        }
        if let items = schema["items"] as? [String: Any] { try checkSchema(items) }
        for branch in schema["anyOf"] as? [[String: Any]] ?? [] { try checkSchema(branch) }
    }
}

private actor StubTransport: HTTPTransport {
    let responseData: Data
    let status: Int
    private(set) var lastRequest: URLRequest?
    init(data: Data, status: Int = 200) { responseData = data; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        return (responseData, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}

private struct FailingTransport: HTTPTransport {
    let code: URLError.Code
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(code) }
}
