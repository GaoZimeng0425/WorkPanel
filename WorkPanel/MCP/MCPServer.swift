// WorkPanel/MCP/MCPServer.swift
import Foundation
import Network

extension Notification.Name {
    /// Posted by SettingsView when MCP enable/port changes so AppDelegate can restart the server.
    static let mcpSettingsChanged = Notification.Name("mcpSettingsChanged")
}

@MainActor
final class MCPServer {
    private let port: UInt16
    private let token: String
    private let dispatcher: MCPDispatcher
    private var listener: NWListener?

    init(port: UInt16, token: String, handlers: MCPToolHandlers) {
        self.port = port
        self.token = token
        self.dispatcher = MCPDispatcher(handlers: handlers)
    }

    /// Pure token check — `nonisolated` so tests and non-async callers can use it freely.
    nonisolated static func authorized(_ headers: [String: String], token: String) -> Bool {
        headers["authorization"] == "Bearer \(token)"
    }

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback   // bind 127.0.0.1 only
        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let l = try? NWListener(using: params, on: nwPort) else { return }
        // Safety: listener runs on queue: .main, so newConnectionHandler fires on the
        // main queue. Use assumeIsolated to re-enter @MainActor without a suspension.
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
        // Safety: listener and connection both run on queue: .main, so this receive
        // completion fires on the main queue. We use MainActor.assumeIsolated to
        // re-enter @MainActor context without a suspension, avoiding the Sendable
        // constraint on NWConnection when crossing actor boundaries.
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isDone, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                var acc = buffer
                if let data { acc.append(data) }
                if let req = HTTPRequest.parse(acc), req.isComplete {
                    Task { await self.respond(conn, to: req) }
                } else if isDone || error != nil {
                    conn.cancel()
                } else {
                    self.receive(conn, buffer: acc)
                }
            }
        }
    }

    private func respond(_ conn: NWConnection, to req: HTTPRequest) async {
        let response: Data
        if req.method == "GET" {
            response = HTTPResponse.methodNotAllowed()
        } else if !Self.authorized(req.headers, token: token) {
            response = HTTPResponse.unauthorized()
        } else {
            switch await dispatcher.handle(req.body) {
            case .body(let data): response = HTTPResponse.json(data)
            case .accepted: response = HTTPResponse.accepted()
            }
        }
        conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
    }
}
