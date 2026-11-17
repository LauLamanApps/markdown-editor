import Foundation

/// Rendering switches, shared by the editor, the Quick Look extension and md2html.
/// Stored in the app's user defaults under the keys below.
struct MarkdownOptions: Equatable {
    enum FrontMatter: String, CaseIterable { case table, code, hidden }

    var math = true
    var mermaid = true
    var footnotes = true
    var highlight = true
    var tableOfContents = true
    var hardLineBreaks = false
    var smartPunctuation = false
    var frontMatter = FrontMatter.table

    enum Key {
        static let math = "MarkdownMath"
        static let mermaid = "MarkdownMermaid"
        static let footnotes = "MarkdownFootnotes"
        static let highlight = "MarkdownHighlight"
        static let tableOfContents = "MarkdownTOC"
        static let hardLineBreaks = "MarkdownHardLineBreaks"
        static let smartPunctuation = "MarkdownSmartPunctuation"
        static let frontMatter = "MarkdownFrontMatter"
    }

    init() {}

    /// Reads options from a defaults dictionary; missing keys keep their defaults.
    init(_ values: [String: Any]) {
        func bool(_ key: String, _ fallback: Bool) -> Bool { values[key] as? Bool ?? fallback }
        math = bool(Key.math, math)
        mermaid = bool(Key.mermaid, mermaid)
        footnotes = bool(Key.footnotes, footnotes)
        highlight = bool(Key.highlight, highlight)
        tableOfContents = bool(Key.tableOfContents, tableOfContents)
        hardLineBreaks = bool(Key.hardLineBreaks, hardLineBreaks)
        smartPunctuation = bool(Key.smartPunctuation, smartPunctuation)
        frontMatter = (values[Key.frontMatter] as? String).flatMap(FrontMatter.init) ?? frontMatter
    }
}
