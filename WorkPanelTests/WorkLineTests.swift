import Testing
@testable import WorkPanel

struct WorkLineTests {
    @Test func extractsPriorityAndTags() {
        let r = WorkLine.parse("写周报 !高 #工作 #紧要")
        #expect(r.title == "写周报")
        #expect(r.priority == .high)
        #expect(r.tags == ["工作", "紧要"])
    }

    @Test func nonTokenWordsStayInTitle() {
        // 时间词不被吃掉,原样留在标题里
        let r = WorkLine.parse("明天 18:00 修复登录bug")
        #expect(r.title == "明天 18:00 修复登录bug")
        #expect(r.priority == nil)
        #expect(r.tags == [])
    }

    @Test func noPriorityTokenYieldsNil() {
        let r = WorkLine.parse("买菜 #生活")
        #expect(r.priority == nil)
        #expect(r.tags == ["生活"])
        #expect(r.title == "买菜")
    }

    @Test func bareHashIsTitleNotTag() {
        let r = WorkLine.parse("# 不是标签")
        #expect(r.tags == [])
        #expect(r.title == "# 不是标签")
    }
}
