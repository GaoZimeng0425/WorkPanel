import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct SyncPeerBrowserTests {
    @Test func isSelfMatchesOwnInstanceID() {
        #expect(SyncPeerBrowser.isSelf(serviceName: "ABC-123", ownInstanceID: "ABC-123") == true)
    }
    @Test func isSelfRejectsOtherInstanceID() {
        #expect(SyncPeerBrowser.isSelf(serviceName: "PEER-999", ownInstanceID: "ABC-123") == false)
    }
}
