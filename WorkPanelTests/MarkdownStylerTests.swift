import Testing
import AppKit
@testable import WorkPanel

@MainActor
struct MarkdownStylerTests {
    // bold span (not on the first line, to avoid the title-style confound) must yield a bold font.
    @Test func boldSpanGetsBoldFont() {
        let storage = NSTextStorage(string: "title\n**x**")
        MarkdownStyler.apply(to: storage)
        // "title\n**x**" -> '*'=6 '*'=7 'x'=8
        let font = storage.attribute(.font, at: 8, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test func italicSpanGetsItalicFont() {
        let storage = NSTextStorage(string: "title\n_y_")
        MarkdownStyler.apply(to: storage)
        // "title\n_y_" -> '_'=6 'y'=7
        let font = storage.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    }
}
