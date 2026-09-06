import Foundation

struct BridgeRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

struct BridgeResponse: Sendable {
    var status: Int
    var body: Data
    var headers: [String: String] = [:]

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> Self {
        .init(status: status, body: (try? JSONEncoder().encode(value)) ?? Data())
    }
    static func error(_ status: Int, _ code: String, _ message: String) -> Self {
        struct Envelope: Encodable { let error: Detail }
        struct Detail: Encodable { let code: String; let message: String }
        return .json(Envelope(error: Detail(code: code, message: message)), status: status)
    }
    var wire: Data {
        let reason = [200: "OK", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
                      404: "Not Found", 405: "Method Not Allowed", 408: "Request Timeout", 413: "Payload Too Large",
                      415: "Unsupported Media Type", 429: "Too Many Requests", 500: "Internal Server Error",
                      502: "Bad Gateway", 503: "Service Unavailable", 504: "Gateway Timeout"][status] ?? "Error"
        var lines = ["HTTP/1.1 \(status) \(reason)", "Content-Type: application/json; charset=utf-8",
                     "Content-Length: \(body.count)", "Connection: close", "Cache-Control: no-store",
                     "X-Content-Type-Options: nosniff"]
        lines += headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body
    }
}

/// One bounded HTTP/1.1 request per connection. No chunking, pipelining or ambiguous headers.
struct BridgeHTTPParser {
    enum Failure: Error { case malformed, tooLarge }
    static let headerLimit = 8_192
    static let bodyLimit = 16_384
    static func parse(_ data: Data) throws -> BridgeRequest? {
        guard data.count <= headerLimit + bodyLimit else { throw Failure.tooLarge }
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > headerLimit { throw Failure.tooLarge }
            return nil
        }
        guard boundary.lowerBound <= headerLimit,
              let head = String(data: data[..<boundary.lowerBound], encoding: .ascii) else { throw Failure.malformed }
        let lines = head.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ", omittingEmptySubsequences: false)
        guard first.count == 3, first[2] == "HTTP/1.1", ["GET", "POST", "OPTIONS"].contains(String(first[0])),
              first[1].hasPrefix("/"), !first[1].contains("?"), !first[1].contains("#") else { throw Failure.malformed }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw Failure.malformed }
            let name = String(line[..<colon]).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }),
                  value.utf8.allSatisfy({ (32...126).contains($0) }), headers[name] == nil else { throw Failure.malformed }
            headers[name] = value
        }
        guard headers["host"] != nil, headers["transfer-encoding"] == nil, headers["expect"] == nil else { throw Failure.malformed }
        let length: Int
        if let raw = headers["content-length"] {
            guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }), let count = Int(raw) else { throw Failure.malformed }
            length = count
        } else {
            guard first[0] != "POST" else { throw Failure.malformed }
            length = 0
        }
        guard length <= bodyLimit else { throw Failure.tooLarge }
        let received = data.count - boundary.upperBound
        guard received <= length else { throw Failure.malformed }
        guard received == length else { return nil }
        return BridgeRequest(method: String(first[0]), path: String(first[1]), headers: headers,
                             body: Data(data[boundary.upperBound...]))
    }
}
