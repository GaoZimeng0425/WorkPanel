import Testing
@testable import WorkPanel

struct MarkdownCheckboxTests {
    @Test func uncheckedBecomesChecked() {
        #expect(MarkdownCheckbox.toggle(in: "标题\n- [ ] 待办", lineIndex: 1) == "标题\n- [x] 待办")
    }

    @Test func checkedBecomesUnchecked() {
        #expect(MarkdownCheckbox.toggle(in: "标题\n- [x] 完成", lineIndex: 1) == "标题\n- [ ] 完成")
        #expect(MarkdownCheckbox.toggle(in: "标题\n- [X] 完成", lineIndex: 1) == "标题\n- [ ] 完成")
    }

    @Test func bareBracketsBecomeChecked() {
        #expect(MarkdownCheckbox.toggle(in: "t\n[] 选择", lineIndex: 1) == "t\n[x] 选择")
    }

    @Test func nonCheckboxLineUnchanged() {
        #expect(MarkdownCheckbox.toggle(in: "标题\n普通一行", lineIndex: 1) == "标题\n普通一行")
    }

    @Test func outOfRangeIndexUnchanged() {
        #expect(MarkdownCheckbox.toggle(in: "只有一行", lineIndex: 5) == "只有一行")
    }

    @Test func onlyTargetLineChanges() {
        let src = "- [ ] a\n- [ ] b"
        #expect(MarkdownCheckbox.toggle(in: src, lineIndex: 0) == "- [x] a\n- [ ] b")
    }
}
