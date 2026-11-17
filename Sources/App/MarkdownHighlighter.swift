import Cocoa

/// Light syntax highlighting for the editor. Re-highlights the whole text on
/// every edit, which is simple and correct for multi-line constructs (code
/// fences) and fast enough for documents of normal size.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {
    var fontSize: CGFloat { didSet { makeFonts() } }

    private(set) var baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private var boldFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
    private var italicFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    /// Above this size only the edited paragraphs are re-highlighted.
    private let fullHighlightLimit = 300_000

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.textColor]
    }

    init(fontSize: CGFloat) {
        self.fontSize = fontSize
        super.init()
        makeFonts()
    }

    private func makeFonts() {
        baseFont = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        boldFont = .monospacedSystemFont(ofSize: fontSize, weight: .bold)
        italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        if textStorage.length > fullHighlightLimit {
            highlight(textStorage, in: (textStorage.string as NSString).paragraphRange(for: editedRange))
        } else {
            highlight(textStorage)
        }
    }

    func highlight(_ storage: NSTextStorage) {
        highlight(storage, in: NSRange(location: 0, length: storage.length))
    }

    private func highlight(_ storage: NSTextStorage, in range: NSRange) {
        let text = storage.string
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: range)

        func apply(_ pattern: NSRegularExpression, group: Int = 0, _ attrs: [NSAttributedString.Key: Any]) {
            pattern.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let r = match?.range(at: group), r.location != NSNotFound else { return }
                storage.addAttributes(attrs, range: r)
            }
        }

        let muted = NSColor.secondaryLabelColor
        let accent = NSColor.controlAccentColor
        let code = NSColor.systemPink

        apply(Self.heading, [.font: boldFont])
        apply(Self.heading, group: 1, [.foregroundColor: accent])
        apply(Self.setextUnderline, [.foregroundColor: accent])
        apply(Self.quote, [.foregroundColor: muted])
        apply(Self.listMarker, group: 1, [.foregroundColor: accent])
        apply(Self.rule, [.foregroundColor: muted])
        apply(Self.bold, [.font: boldFont])
        apply(Self.italic, [.font: italicFont])
        apply(Self.strike, [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: muted])
        apply(Self.link, group: 1, [.foregroundColor: NSColor.linkColor])
        apply(Self.link, group: 2, [.foregroundColor: muted])
        apply(Self.inlineCode, [.foregroundColor: code])

        // Code fences and front matter win over everything inside them
        for block in Self.codeBlocks(in: text as NSString) where NSIntersectionRange(block, range).length > 0 {
            let r = NSIntersectionRange(block, range)
            storage.setAttributes([.font: baseFont, .foregroundColor: code], range: r)
        }
        if let fm = Self.frontMatter(in: text as NSString), NSIntersectionRange(fm, range).length > 0 {
            storage.setAttributes([.font: baseFont, .foregroundColor: muted], range: NSIntersectionRange(fm, range))
        }
        storage.endEditing()
    }

    private static func regex(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.anchorsMatchLines])
    }

    private static let heading = regex(#"^ {0,3}(#{1,6})\s.*$"#)
    private static let setextUnderline = regex(#"(?<=\S\n) {0,3}(?:=+|-+)[ \t]*$"#)
    private static let quote = regex(#"^ {0,3}>.*$"#)
    private static let listMarker = regex(#"^\s*([-*+]|\d+[.)])(?:\s+\[[ xX]\])?\s"#)
    private static let rule = regex(#"^ {0,3}([-*_])(\s*\1){2,}\s*$"#)
    private static let bold = regex(#"(\*\*|__)(?=\S)[^\n]+?(?<=\S)\1"#)
    private static let italic = regex(#"(?<![*\w])\*(?![\s*])[^*\n]+?(?<![\s*])\*(?![*\w])|(?<![_\w])_(?![\s_])[^_\n]+?(?<![\s_])_(?![_\w])"#)
    private static let strike = regex(#"~~(?=\S)[^~\n]+?(?<=\S)~~"#)
    private static let link = regex(#"!?(\[[^\]\n]*\])(\([^)\n]*\))"#)
    private static let inlineCode = regex(#"(`+)[^`\n]+?\1"#)

    /// Ranges of fenced code blocks, including the fences.
    private static func codeBlocks(in text: NSString) -> [NSRange] {
        var blocks: [NSRange] = []
        var open: (start: Int, fence: String)?
        var location = 0
        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let line = text.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if let o = open {
                if line.hasPrefix(o.fence), line.allSatisfy({ $0 == o.fence.first }) {
                    blocks.append(NSRange(location: o.start, length: NSMaxRange(lineRange) - o.start))
                    open = nil
                }
            } else if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let ch = line.first!
                open = (lineRange.location, String(line.prefix(while: { $0 == ch })))
            }
            location = NSMaxRange(lineRange)
        }
        if let o = open { blocks.append(NSRange(location: o.start, length: text.length - o.start)) }
        return blocks
    }

    private static func frontMatter(in text: NSString) -> NSRange? {
        guard text.hasPrefix("---\n") else { return nil }
        let rest = text.range(of: "\n---", options: [], range: NSRange(location: 3, length: text.length - 3))
        guard rest.location != NSNotFound else { return nil }
        let end = text.lineRange(for: NSRange(location: rest.location + 1, length: 0))
        return NSRange(location: 0, length: NSMaxRange(end))
    }
}
