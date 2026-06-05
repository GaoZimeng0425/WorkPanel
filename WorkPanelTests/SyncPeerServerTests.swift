import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct SyncPeerServerTests {
    private func request(method: String, path: String, code: String?) -> HTTPRequest {
        var headers: [String: String] = [:]
        if let code { headers["authorization"] = "Bearer \(code)" }
        return HTTPRequest(method: method, path: path, headers: headers, body: Data())
    }
    private func status(of response: Data) -> Int {
        let head = String(decoding: response, as: UTF8.self)
        let line = head.components(separatedBy: "\r\n").first ?? ""
        return Int(line.split(separator: " ").dropFirst().first.map(String.init) ?? "") ?? 0
    }

    @Test func validGetSyncReturns200WithBody() {
        let resp = SyncPeerServer.route(request(method: "GET", path: "/sync", code: "secret"),
                                        code: "secret", body: { Data("{}".utf8) })
        #expect(status(of: resp) == 200)
    }
    @Test func wrongCodeReturns401() {
        let resp = SyncPeerServer.route(request(method: "GET", path: "/sync", code: "wrong"),
                                        code: "secret", body: { Data("{}".utf8) })
        #expect(status(of: resp) == 401)
    }
    @Test func missingCodeReturns401() {
        let resp = SyncPeerServer.route(request(method: "GET", path: "/sync", code: nil),
                                        code: "secret", body: { Data("{}".utf8) })
        #expect(status(of: resp) == 401)
    }
    @Test func nonGetReturns405() {
        let resp = SyncPeerServer.route(request(method: "POST", path: "/sync", code: "secret"),
                                        code: "secret", body: { Data("{}".utf8) })
        #expect(status(of: resp) == 405)
    }
    @Test func unknownPathReturns404() {
        let resp = SyncPeerServer.route(request(method: "GET", path: "/nope", code: "secret"),
                                        code: "secret", body: { Data("{}".utf8) })
        #expect(status(of: resp) == 404)
    }
}
