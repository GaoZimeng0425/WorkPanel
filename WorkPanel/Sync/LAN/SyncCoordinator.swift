import Foundation
import SwiftData
import Observation

/// 给设置面板观察的实时状态(SwiftUI Observation 自动刷新)。
@MainActor
@Observable
final class LANSyncStatus {
    static let shared = LANSyncStatus()
    var isRunning = false
    var peerNames: [String] = []
    var lastSync: String = "尚未同步"
    private init() {}
}

/// 局域网自动同步协调器:持有 server + browser + 轮询定时器;到点 / 发现新对端即拉取并合并。
/// 由 AppDelegate 按设置启停,生命周期与 MCPServer 一致。
@MainActor
final class SyncCoordinator {
    private let context: ModelContext
    private let code: String
    private let intervalSeconds: Int
    private let server: SyncPeerServer
    private var browser: SyncPeerBrowser?
    private var timer: Timer?
    private let status = LANSyncStatus.shared

    init(context: ModelContext) {
        self.context = context
        self.code = AppSettings.lanSyncPairingCode
        self.intervalSeconds = AppSettings.lanSyncIntervalSeconds
        self.server = SyncPeerServer(port: UInt16(AppSettings.lanSyncPort),
                                     code: code,
                                     instanceID: AppSettings.syncInstanceID,
                                     deviceName: AppSettings.lanSyncDeviceName,
                                     context: context)
    }

    func start() {
        guard timer == nil else { return }   // 已在运行则不重复启动(防重复 timer / 泄漏 browser)
        server.start()
        browser = SyncPeerBrowser(ownInstanceID: AppSettings.syncInstanceID) { [weak self] peers in
            guard let self else { return }
            self.status.peerNames = peers.map(\.deviceName)
            self.syncAll(peers)                 // 发现变化即同步一轮
        }
        browser?.start()
        let t = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalSeconds), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.syncAll(self.browser?.peers ?? [])
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        status.isRunning = true
    }

    func stop() {
        timer?.invalidate(); timer = nil
        browser?.stop(); browser = nil
        server.stop()
        status.isRunning = false
        status.peerNames = []
    }

    private func syncAll(_ peers: [DiscoveredPeer]) {
        guard !code.isEmpty else { status.lastSync = "未设置配对码"; return }
        for peer in peers {
            Task { [weak self] in
                guard let self else { return }
                do {
                    let doc = try await SyncClient.fetch(from: peer.endpoint, code: self.code)
                    let report = try SyncService.merge(doc, into: self.context, includeSettings: false)
                    self.status.lastSync = "已同步 \(peer.deviceName):新增 \(report.totalInserted),更新 \(report.totalUpdated)"
                } catch {
                    self.status.lastSync = "同步 \(peer.deviceName) 失败"
                }
            }
        }
    }
}
