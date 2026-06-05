import Foundation
import Network
import SwiftData

/// 绑局域网的 HTTP 服务,Bonjour 广播 `_workpanel._tcp`,应答 `GET /sync`(配对码鉴权)。
/// 独立于只绑 loopback 的 MCPServer——避免把 MCP 工具暴露到网络。
@MainActor
final class SyncPeerServer {
    private let port: UInt16
    private let code: String
    private let instanceID: String
    private let deviceName: String
    private let context: ModelContext
    private var listener: NWListener?

    init(port: UInt16, code: String, instanceID: String, deviceName: String, context: ModelContext) {
        self.port = port
        self.code = code
        self.instanceID = instanceID
        self.deviceName = deviceName
        self.context = context
    }

    /// 纯路由:GET /sync + 正确配对码 → 200 + body();非 GET → 405;配对码错/缺 → 401;其它路径 → 404。
    static func route(_ req: HTTPRequest, code: String, body: () throws -> Data) -> Data {
        guard req.method == "GET" else { return HTTPResponse.methodNotAllowed() }
        guard MCPServer.authorized(req.headers, token: code) else { return HTTPResponse.unauthorized() }
        guard req.path == "/sync" else { return HTTPResponse.build(status: 404, reason: "Not Found") }
        do { return HTTPResponse.json(try body()) }
        catch { return HTTPResponse.build(status: 500, reason: "Internal Server Error") }
    }

    func start() {
        guard listener == nil else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let l = try? NWListener(using: .tcp, on: nwPort) else { return }
        var txt = NWTXTRecord()
        txt["device"] = deviceName
        l.service = NWListener.Service(name: instanceID, type: "_workpanel._tcp",
                                       domain: nil, txtRecord: txt.data)
        l.newConnectionHandler = { [weak self] conn in
            MainActor.assumeIsolated { self?.accept(conn) }
        }
        l.start(queue: .main)
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .main)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isDone, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                var acc = buffer
                if let data { acc.append(data) }
                if let req = HTTPRequest.parse(acc), req.isComplete {
                    let resp = Self.route(req, code: self.code) {
                        try SyncService.exportData(context: self.context, includeSettings: false)
                    }
                    conn.send(content: resp, completion: .contentProcessed { _ in conn.cancel() })
                } else if isDone || error != nil {
                    conn.cancel()
                } else {
                    self.receive(conn, buffer: acc)
                }
            }
        }
    }
}
