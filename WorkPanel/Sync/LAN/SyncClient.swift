import Foundation
import Network

/// 向对端发 `GET /sync` 并把响应解析为 SyncDocument。
@MainActor
enum SyncClient {
    enum ClientError: Error, Equatable {
        case malformed
        case http(Int)
        case connectionLost
    }

    /// 纯函数:整段 HTTP 响应字节 → SyncDocument。状态非 200 抛 .http;无法解析抛 .malformed;
    /// body 非法或版本不符由 SyncService.parse 抛出。
    /// @MainActor 因为 SyncService.parse 是 @MainActor;测试与 fetch 调用点均已在 MainActor 上下文。
    static func parseResponse(_ data: Data) throws -> SyncDocument {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
              let headerString = String(data: data.subdata(in: data.startIndex..<headerEnd.lowerBound),
                                        encoding: .utf8),
              let statusLine = headerString.components(separatedBy: "\r\n").first
        else { throw ClientError.malformed }
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, let status = Int(parts[1]) else { throw ClientError.malformed }
        guard status == 200 else { throw ClientError.http(status) }
        let body = data.subdata(in: headerEnd.upperBound..<data.endIndex)
        return try SyncService.parse(body)
    }

    /// 实时:连到对端 Bonjour 端点,发 GET /sync(带配对码),累积响应直到完整或连接关闭,解析返回。
    /// 实时 socket 部分不单测;以编译 + 双机手动验证。
    static func fetch(from endpoint: NWEndpoint, code: String,
                      timeout: TimeInterval = 5) async throws -> SyncDocument {
        let conn = NWConnection(to: endpoint, using: .tcp)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<SyncDocument, Error>) in
            var finished = false
            // 用 @MainActor @Sendable 闭包(而非普通嵌套 func)以满足 NWConnection 的 @Sendable
            // 回调捕获约束;运行时它们都在 queue: .main 上经 assumeIsolated 再入,捕获是安全的。
            let finish: @MainActor @Sendable (Result<SyncDocument, Error>) -> Void = { result in
                guard !finished else { return }
                finished = true
                conn.cancel()
                cont.resume(with: result)
            }

            let request = "GET /sync HTTP/1.1\r\nHost: workpanel\r\nAuthorization: Bearer \(code)\r\nConnection: close\r\n\r\n"

            conn.stateUpdateHandler = { state in
                MainActor.assumeIsolated {
                    switch state {
                    case .ready:
                        conn.send(content: Data(request.utf8),
                                  completion: .contentProcessed { sendErr in
                                      MainActor.assumeIsolated {
                                          if let sendErr { finish(.failure(sendErr)) }
                                          else { receive(conn, Data(), finish) }
                                      }
                                  })
                    case .failed(let e):
                        finish(.failure(e))
                    case .cancelled:
                        // 连接异常中断(对端消失等)。超时路径自身的 cancel 已被 finished 守卫吞掉,不会走到这。
                        finish(.failure(ClientError.connectionLost))
                    default:
                        break
                    }
                }
            }
            conn.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(ClientError.http(408)))
            }
        }
    }

    /// 累积响应字节,直到 body 完整或连接关闭再解析。提为静态方法(而非嵌套自递归 func)
    /// 以避免可变局部捕获被 @Sendable 回调送出而触发的数据竞争检查。所有回调都在 queue: .main 上经
    /// assumeIsolated 再入。
    private static func receive(_ conn: NWConnection, _ buffer: Data,
                                _ finish: @escaping @MainActor @Sendable (Result<SyncDocument, Error>) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isDone, error in
            MainActor.assumeIsolated {
                var acc = buffer
                if let data { acc.append(data) }
                // 复用 HTTPRequest.parse 仅为判定 body 是否按 Content-Length 收齐(响应行形态兼容,
                // 真正的状态码/解析在 parseResponse 里);服务端总会带 Content-Length,否则靠下面的 isDone 兜底。
                if let req = HTTPRequest.parse(acc), req.isComplete {
                    finish(Result { try Self.parseResponse(acc) })
                } else if isDone {
                    finish(Result { try Self.parseResponse(acc) })
                } else if let error {
                    finish(.failure(error))
                } else {
                    receive(conn, acc, finish)
                }
            }
        }
    }
}
