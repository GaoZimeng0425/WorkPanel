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

    // 屏幕坐标 y 向上:光标上移 → 看板变高,1:1 跟手。
    @Test func resizeFollowsCursorOneToOne() {
        #expect(BoardPanelController.resizedHeight(startHeight: 400, startMouseY: 100,
                                                   currentMouseY: 150, min: 360, max: 900) == 450)
    }

    @Test func resizeShrinksWhenCursorMovesDown() {
        #expect(BoardPanelController.resizedHeight(startHeight: 400, startMouseY: 100,
                                                   currentMouseY: 70, min: 360, max: 900) == 370)
    }

    @Test func resizeClampsToMax() {
        #expect(BoardPanelController.resizedHeight(startHeight: 800, startMouseY: 100,
                                                   currentMouseY: 400, min: 360, max: 900) == 900)
    }
}
