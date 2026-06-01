// WorkPanel/MCP/HTTPMessage.swift
import Foundation

struct HTTPRequest {
    nonisolated let method: String
    nonisolated let path: String
    nonisolated let headers: [String: String]   // keys lowercased
    nonisolated let body: Data

    /// Parses an HTTP/1.1 request. Returns nil if the header block is not yet complete.
    nonisolated static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: data.startIndex..<headerEnd.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        let body = data.subdata(in: headerEnd.upperBound..<data.endIndex)
        return HTTPRequest(method: String(parts[0]), path: String(parts[1]),
                           headers: headers, body: body)
    }

    /// Whether the full body (per Content-Length) has arrived.
    nonisolated var isComplete: Bool {
        let expected = Int(headers["content-length"] ?? "0") ?? 0
        return body.count >= expected
    }
}

enum HTTPResponse {
    nonisolated static func build(status: Int, reason: String,
                      headers: [String: String] = [:], body: Data = Data()) -> Data {
        var allHeaders = headers
        allHeaders["Content-Length"] = String(body.count)
        allHeaders["Connection"] = "close"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        for (k, v) in allHeaders { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }

    nonisolated static func json(_ body: Data) -> Data {
        build(status: 200, reason: "OK",
              headers: ["Content-Type": "application/json"], body: body)
    }
    nonisolated static func accepted() -> Data { build(status: 202, reason: "Accepted") }
    nonisolated static func unauthorized() -> Data { build(status: 401, reason: "Unauthorized") }
    nonisolated static func methodNotAllowed() -> Data { build(status: 405, reason: "Method Not Allowed") }
}
