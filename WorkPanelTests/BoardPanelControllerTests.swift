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

    // 80% 居中贴底:1600 宽屏 → 1280 宽、x=160、底边 +16。
    @Test func boardFrameUsesPercentAndCenters() {
        let visible = NSRect(x: 0, y: 0, width: 1600, height: 900)
        let frame = BoardPanelController.boardFrame(visible: visible, height: 500,
                                                    percent: 0.8, minWidth: 760, margin: 16)
        #expect(frame.width == 1280)
        #expect(frame.origin.x == 160)
        #expect(frame.origin.y == 16)
        #expect(frame.height == 500)
    }

    // 百分比算出来比 760 窄 → 用最小宽,仍居中。
    @Test func boardFrameFloorsAtMinWidth() {
        let visible = NSRect(x: 0, y: 0, width: 1200, height: 900)
        let frame = BoardPanelController.boardFrame(visible: visible, height: 500,
                                                    percent: 0.5, minWidth: 760, margin: 16)
        #expect(frame.width == 760)
        #expect(frame.origin.x == 220)
    }

    // 小屏(宽 700)连最小宽都放不下 → 退让到屏宽,x=0,不得越界。
    @Test func boardFrameNeverExceedsVisibleWidth() {
        let visible = NSRect(x: 100, y: 40, width: 700, height: 600)
        let frame = BoardPanelController.boardFrame(visible: visible, height: 420,
                                                    percent: 0.5, minWidth: 760, margin: 16)
        #expect(frame.width == 700)
        #expect(frame.origin.x == 100)
        #expect(frame.origin.y == 56)
    }
}
