import Testing
import AppKit
@testable import WorkPanel

@MainActor
struct BoardPanelControllerTests {
    @Test func clampReturnsValueWithinRange() {
        #expect(BoardPanelController.clampHeight(500, min: 360, max: 900) == 500)
    }

    @Test func clampFloorsAtMin() {
        #expect(BoardPanelController.clampHeight(100, min: 360, max: 900) == 360)
    }

    @Test func clampCeilingsAtMax() {
        #expect(BoardPanelController.clampHeight(1200, min: 360, max: 900) == 900)
    }
}
