import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct SyncClientTests {
    /// 构造一个最小合法 SyncDocument 的 JSON body。
    private func docBody() throws -> Data {
        let doc = SyncDocument(schemaVersion: 1, exportedAt: Date(timeIntervalSince1970: 0),
                               tasks: [], columns: [], dayPlans: [], settings: SyncSettingsDTO())
        return try SyncDocument.encoder.encode(doc)
    }

    private func response(status: Int, reason: String, body: Data) -> Data {
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    @Test func parsesValid200Response() throws {
        let resp = response(status: 200, reason: "OK", body: try docBody())
        let doc = try SyncClient.parseResponse(resp)
        #expect(doc.schemaVersion == 1)
    }

    @Test func throwsOnNon200() throws {
        let resp = response(status: 401, reason: "Unauthorized", body: Data())
        #expect(throws: SyncClient.ClientError.self) {
            try SyncClient.parseResponse(resp)
        }
    }

    @Test func throwsOnMalformedResponse() {
        #expect(throws: (any Error).self) {
            try SyncClient.parseResponse(Data("garbage no crlf".utf8))
        }
    }

    @Test func throwsOnUnknownSchemaBody() throws {
        let bad = Data(#"{"schemaVersion":999,"exportedAt":"2026-01-01T00:00:00Z","tasks":[],"columns":[],"dayPlans":[],"settings":{}}"#.utf8)
        let resp = response(status: 200, reason: "OK", body: bad)
        #expect(throws: (any Error).self) {   // SyncService.parse 拒绝未知版本
            try SyncClient.parseResponse(resp)
        }
    }
}
