import XCTest

/// 看板的 UI 冒烟测试:以 `--uitest` 启动(内存库 + 注入 任务A/B/C 于「计划中」并自动弹出看板),
/// 断言看板正确渲染——三列就位、三张卡片就位且都在「计划中」列。
///
/// 为什么这里不测拖拽:SwiftUI 的 `.draggable`/`.dropDestination` 走 NSItemProvider 拖拽会话,
/// 而 XCUITest 的合成指针事件无法发起该会话(平台限制,已实测两种手势均无效)。拖拽落位的
/// 正确性由 `BoardStoreTests` 单元测试覆盖。
final class BoardUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBoardLaunchesWithSeededColumnsAndCards() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--uitest"]
        app.launch()

        // 三列就位
        for column in ["计划中", "开发中", "测试中"] {
            XCTAssertTrue(app.staticTexts[column].waitForExistence(timeout: 10),
                          "未找到列「\(column)」")
        }

        // 三张卡片就位,且都落在「计划中」列
        for title in ["任务A", "任务B", "任务C"] {
            let card = app.descendants(matching: .any)["card-\(title)"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5), "未找到卡片 \(title)")
            XCTAssertEqual(nearestColumn(to: card.frame.midX, in: app), "计划中",
                           "\(title) 应在计划中列")
        }
    }

    /// 用三列表头横向中心做锚点,返回离给定 x 最近的列名。
    @MainActor
    private func nearestColumn(to x: CGFloat, in app: XCUIApplication) -> String {
        ["计划中", "开发中", "测试中"]
            .map { ($0, app.staticTexts[$0].frame.midX) }
            .min { abs($0.1 - x) < abs($1.1 - x) }!
            .0
    }
}
