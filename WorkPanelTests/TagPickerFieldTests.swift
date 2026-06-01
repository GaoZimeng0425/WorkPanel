import Testing
@testable import WorkPanel

struct TagPickerFieldTests {
    @Test func summaryEmptyIsPlaceholder() {
        #expect(TagPickerField.summary([]) == "标签")
    }
    @Test func summaryUpToThreeJoinsNames() {
        #expect(TagPickerField.summary(["工作"]) == "工作")
        #expect(TagPickerField.summary(["工作", "学习"]) == "工作 学习")
        #expect(TagPickerField.summary(["工作", "学习", "紧急"]) == "工作 学习 紧急")
    }
    @Test func summaryOverThreeCollapses() {
        #expect(TagPickerField.summary(["工作", "学习", "紧急", "家庭"]) == "工作 等4个标签")
    }
}
