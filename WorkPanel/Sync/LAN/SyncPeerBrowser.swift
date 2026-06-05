import Foundation
import Network

/// 一个发现到的对端:Bonjour 端点 + 实例名 + 设备名(供展示)。
struct DiscoveredPeer: Identifiable, Equatable {
    let id: String          // 实例名(= 对端 syncInstanceID)
    let deviceName: String
    let endpoint: NWEndpoint

    static func == (a: DiscoveredPeer, b: DiscoveredPeer) -> Bool { a.id == b.id }
}

/// 浏览 `_workpanel._tcp`,维护对端列表(过滤自身),变化时回调。
@MainActor
final class SyncPeerBrowser {
    private let ownInstanceID: String
    private let onChange: ([DiscoveredPeer]) -> Void
    private var browser: NWBrowser?
    private(set) var peers: [DiscoveredPeer] = []

    init(ownInstanceID: String, onChange: @escaping ([DiscoveredPeer]) -> Void) {
        self.ownInstanceID = ownInstanceID
        self.onChange = onChange
    }

    /// 纯函数:Bonjour 服务实例名是否就是本机(用于过滤自己)。
    nonisolated static func isSelf(serviceName: String, ownInstanceID: String) -> Bool {
        serviceName == ownInstanceID
    }

    func start() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_workpanel._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.update(results) }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
        peers = []
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var found: [DiscoveredPeer] = []
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            guard !Self.isSelf(serviceName: name, ownInstanceID: ownInstanceID) else { continue }
            var device = name
            if case let .bonjour(txt) = result.metadata, let d = txt["device"] { device = d }
            found.append(DiscoveredPeer(id: name, deviceName: device, endpoint: result.endpoint))
        }
        guard found != peers else { return }   // 集合无变化则不触发,避免每次浏览刷新都引发一轮同步
        peers = found
        onChange(found)
    }
}
