import Foundation

/// Small, dependency-free Markdown → HTML renderer.
///
/// Covers CommonMark basics plus the GitHub-flavoured extensions people
/// actually use in READMEs: tables, task lists, strikethrough, autolinks,
/// fenced code, alerts (`> [!NOTE]`) and YAML front matter.
public struct MarkdownRenderer {
    /// Resolves an image `src` to something the preview can display
    /// (e.g. a data: URI). Return nil to keep the original src.
    public var imageResolver: ((String) -> String?)?

    private var references: [String: (url: String, title: String?)] = [:]

    public init(imageResolver: ((String) -> String?)? = nil) {
        self.imageResolver = imageResolver
    }

    public mutating func render(_ markdown: String) -> String {
        var text = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        var lines = text.components(separatedBy: "\n")
        var html = ""

        if let (frontMatter, rest) = Self.extractFrontMatter(lines) {
            html += "<pre class=\"front-matter\"><code>\(escape(frontMatter.joined(separator: "\n")))</code></pre>\n"
            lines = rest
        }

        lines = collectReferences(lines)
        html += renderBlocks(lines, tight: false)
        return html
    }

    // MARK: - Front matter & references

    private static func extractFrontMatter(_ lines: [String]) -> ([String], [String])? {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        for i in 1..<lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t == "---" || t == "..." {
                return (Array(lines[1..<i]), Array(lines[(i + 1)...]))
            }
        }
        return nil
    }

    private static let referenceRegex = try! NSRegularExpression(
        pattern: #"^ {0,3}\[([^\]]+)\]:\s*<?([^\s>]+)>?(?:\s+(?:"([^"]*)"|'([^']*)'|\(([^)]*)\)))?\s*$"#)

    /// Strips link reference definitions (outside code fences) and records them.
    private mutating func collectReferences(_ lines: [String]) -> [String] {
        var out: [String] = []
        var fence: String?
        for line in lines {
            if let f = fence {
                if Self.isFenceClose(line, fence: f) { fence = nil }
                out.append(line)
                continue
            }
            if let open = Self.fenceOpen(line) {
                fence = open.fence
                out.append(line)
                continue
            }
            let ns = line as NSString
            if let m = Self.referenceRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               !line.hasPrefix(" [^") && !line.hasPrefix("[^") {
                let label = ns.substring(with: m.range(at: 1)).lowercased()
                let url = ns.substring(with: m.range(at: 2))
                var title: String?
                for g in 3...5 where m.range(at: g).location != NSNotFound {
                    title = ns.substring(with: m.range(at: g))
                }
                if references[label] == nil { references[label] = (url, title) }
                continue
            }
            out.append(line)
        }
        return out
    }

    // MARK: - Block level

    private func renderBlocks(_ lines: [String], tight: Bool) -> String {
        var html = ""
        var i = 0
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let content = renderInline(paragraph.map { $0.trimmingLeadingSpaces() }.joined(separator: "\n"))
            html += tight ? content + "\n" : "<p>\(content)</p>\n"
            paragraph.removeAll()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // Setext headings (paragraph followed by === or ---)
            if !paragraph.isEmpty, line.leadingSpaces < 4 {
                if Self.matches(trimmed, #"^=+$"#) {
                    let content = renderInline(paragraph.map { $0.trimmingLeadingSpaces() }.joined(separator: "\n"))
                    paragraph.removeAll()
                    html += heading(1, content)
                    i += 1
                    continue
                }
                if Self.matches(trimmed, #"^-+$"#) {
                    let content = renderInline(paragraph.map { $0.trimmingLeadingSpaces() }.joined(separator: "\n"))
                    paragraph.removeAll()
                    html += heading(2, content)
                    i += 1
                    continue
                }
            }

            // Indented code block (cannot interrupt a paragraph)
            if paragraph.isEmpty, line.leadingSpaces >= 4 {
                var code: [String] = []
                while i < lines.count {
                    let l = lines[i]
                    if l.leadingSpaces >= 4 {
                        code.append(String(l.dropFirst(4)))
                    } else if l.trimmingCharacters(in: .whitespaces).isEmpty {
                        code.append("")
                    } else {
                        break
                    }
                    i += 1
                }
                while code.last?.isEmpty == true { code.removeLast() }
                html += "<pre><code>\(escape(code.joined(separator: "\n")))</code></pre>\n"
                continue
            }

            // Fenced code block
            if let open = Self.fenceOpen(line) {
                flushParagraph()
                var code: [String] = []
                i += 1
                while i < lines.count, !Self.isFenceClose(lines[i], fence: open.fence) {
                    code.append(lines[i].removingLeadingSpaces(upTo: open.indent))
                    i += 1
                }
                i += 1 // closing fence
                let lang = open.info.split(separator: " ").first.map(String.init) ?? ""
                let cls = lang.isEmpty ? "" : " class=\"language-\(escapeAttr(lang))\""
                html += "<pre><code\(cls)>\(escape(code.joined(separator: "\n")))</code></pre>\n"
                continue
            }

            // ATX heading
            if let (level, text) = Self.atxHeading(line) {
                flushParagraph()
                html += heading(level, renderInline(text))
                i += 1
                continue
            }

            // Thematic break
            if Self.isThematicBreak(line) {
                flushParagraph()
                html += "<hr>\n"
                i += 1
                continue
            }

            // Blockquote
            if line.leadingSpaces < 4, trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while i < lines.count {
                    let l = lines[i]
                    let t = l.trimmingCharacters(in: .whitespaces)
                    if l.leadingSpaces < 4, t.hasPrefix(">") {
                        var rest = String(t.dropFirst())
                        if rest.hasPrefix(" ") { rest.removeFirst() }
                        quoted.append(rest)
                    } else if !t.isEmpty, let last = quoted.last, !last.trimmingCharacters(in: .whitespaces).isEmpty,
                              !Self.startsBlock(l) {
                        quoted.append(l) // lazy continuation
                    } else {
                        break
                    }
                    i += 1
                }
                html += blockquote(quoted)
                continue
            }

            // Table
            if line.contains("|"), i + 1 < lines.count, let aligns = Self.tableAlignments(lines[i + 1]) {
                let header = Self.splitRow(line)
                if header.count == aligns.count {
                    flushParagraph()
                    i += 2
                    var rows: [[String]] = []
                    while i < lines.count {
                        let l = lines[i]
                        let t = l.trimmingCharacters(in: .whitespaces)
                        if t.isEmpty || !l.contains("|") && Self.startsBlock(l) { break }
                        rows.append(Self.splitRow(l))
                        i += 1
                    }
                    html += table(header: header, aligns: aligns, rows: rows)
                    continue
                }
            }

            // List
            if let marker = Self.listMarker(line) {
                // Lists may only interrupt a paragraph if non-empty and (bullet or starting at 1)
                let canInterrupt = !marker.isEmptyItem && (marker.ordered == false || marker.start == 1)
                if paragraph.isEmpty || canInterrupt {
                    flushParagraph()
                    let (listHTML, next) = list(lines, from: i, first: marker)
                    html += listHTML
                    i = next
                    continue
                }
            }

            // HTML block
            if paragraph.isEmpty, line.leadingSpaces < 4, Self.isHTMLBlockStart(trimmed) {
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    html += lines[i] + "\n"
                    i += 1
                }
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        return html
    }

    private func heading(_ level: Int, _ content: String) -> String {
        let id = Self.slug(content)
        return "<h\(level) id=\"\(id)\">\(content)</h\(level)>\n"
    }

    private func blockquote(_ lines: [String]) -> String {
        var lines = lines
        if let first = lines.first?.trimmingCharacters(in: .whitespaces),
           let m = Self.firstMatch(first, #"^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]$"#, ignoreCase: true) {
            let kind = m[1].lowercased()
            lines.removeFirst()
            let title = kind.prefix(1).uppercased() + kind.dropFirst()
            return "<div class=\"alert alert-\(kind)\"><p class=\"alert-title\">\(title)</p>\n\(renderBlocks(lines, tight: false))</div>\n"
        }
        return "<blockquote>\n\(renderBlocks(lines, tight: false))</blockquote>\n"
    }

    private func table(header: [String], aligns: [String?], rows: [[String]]) -> String {
        func cell(_ tag: String, _ text: String, _ align: String?) -> String {
            let style = align.map { " style=\"text-align:\($0)\"" } ?? ""
            return "<\(tag)\(style)>\(renderInline(text))</\(tag)>"
        }
        var html = "<table>\n<thead><tr>"
        for (k, h) in header.enumerated() { html += cell("th", h, aligns[k]) }
        html += "</tr></thead>\n"
        if !rows.isEmpty {
            html += "<tbody>\n"
            for row in rows {
                html += "<tr>"
                for k in 0..<header.count { html += cell("td", k < row.count ? row[k] : "", aligns[k]) }
                html += "</tr>\n"
            }
            html += "</tbody>\n"
        }
        return html + "</table>\n"
    }

    // MARK: Lists

    private struct ListMarker {
        var ordered: Bool
        var char: Character      // '-', '*', '+', '.', ')'
        var start: Int
        var indent: Int          // spaces before marker
        var contentIndent: Int   // column where item content starts
        var content: String
        var isEmptyItem: Bool { content.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func listMarker(_ line: String) -> ListMarker? {
        let indent = line.leadingSpaces
        guard indent < 4 else { return nil }
        let body = Array(line.dropFirst(indent))
        guard !body.isEmpty else { return nil }

        var markerLen: Int
        var ordered = false
        var char: Character
        var start = 1

        if "-*+".contains(body[0]) {
            char = body[0]
            markerLen = 1
        } else {
            var digits = ""
            var k = 0
            while k < body.count, k < 9, body[k].isASCII, body[k].isNumber { digits.append(body[k]); k += 1 }
            guard !digits.isEmpty, k < body.count, body[k] == "." || body[k] == ")" else { return nil }
            ordered = true
            char = body[k]
            start = Int(digits) ?? 1
            markerLen = k + 1
        }

        // Marker must be followed by space or end of line
        if markerLen < body.count {
            guard body[markerLen] == " " else { return nil }
        }
        var spaces = 0
        while markerLen + spaces < body.count, body[markerLen + spaces] == " " { spaces += 1 }
        let rest = String(body.dropFirst(markerLen + spaces))
        if spaces > 4 || rest.isEmpty { spaces = 1 } // indented code inside item / empty item
        return ListMarker(ordered: ordered, char: char, start: start, indent: indent,
                          contentIndent: indent + markerLen + spaces,
                          content: rest)
    }

    private func list(_ lines: [String], from startIndex: Int, first: ListMarker) -> (String, Int) {
        var items: [[String]] = []
        var i = startIndex
        var loose = false
        var current: [String] = [first.content]
        var contentIndent = first.contentIndent
        var sawBlank = false
        i += 1

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                sawBlank = true
                current.append("")
                i += 1
                continue
            }

            if line.leadingSpaces >= contentIndent {
                if sawBlank, current.contains(where: { !$0.isEmpty }) { loose = true }
                sawBlank = false
                current.append(line.removingLeadingSpaces(upTo: contentIndent))
                i += 1
                continue
            }

            if let m = Self.listMarker(line), m.ordered == first.ordered, m.char == first.char,
               !Self.isThematicBreak(line) {
                if sawBlank { loose = true }
                sawBlank = false
                items.append(current)
                current = [m.content]
                contentIndent = m.contentIndent
                i += 1
                continue
            }

            // Lazy paragraph continuation
            if !sawBlank, !Self.startsBlock(line), let last = current.last, !last.isEmpty {
                current.append(line)
                i += 1
                continue
            }
            break
        }
        items.append(current)

        var html = first.ordered
            ? (first.start != 1 ? "<ol start=\"\(first.start)\">\n" : "<ol>\n")
            : "<ul>\n"
        for var item in items {
            while item.last?.isEmpty == true { item.removeLast() }
            var checkbox = ""
            if let firstLine = item.first,
               let m = Self.firstMatch(firstLine, #"^\[([ xX])\]\s+(.*)$"#) {
                let checked = m[1] != " "
                checkbox = "<input type=\"checkbox\" disabled\(checked ? " checked" : "")> "
                item[0] = m[2]
            }
            let cls = checkbox.isEmpty ? "" : " class=\"task-list-item\""
            var inner = renderBlocks(item, tight: !loose)
            if !loose, inner.hasSuffix("\n") { inner.removeLast() }
            if !checkbox.isEmpty {
                if loose, inner.hasPrefix("<p>") {
                    inner = "<p>" + checkbox + inner.dropFirst(3)
                } else {
                    inner = checkbox + inner
                }
            }
            html += "<li\(cls)>\(inner)</li>\n"
        }
        html += first.ordered ? "</ol>\n" : "</ul>\n"
        return (html, i)
    }

    // MARK: Block helpers

    private static func fenceOpen(_ line: String) -> (fence: String, info: String, indent: Int)? {
        let indent = line.leadingSpaces
        guard indent < 4 else { return nil }
        let body = line.dropFirst(indent)
        guard let c = body.first, c == "`" || c == "~" else { return nil }
        let run = body.prefix(while: { $0 == c })
        guard run.count >= 3 else { return nil }
        let info = body.dropFirst(run.count).trimmingCharacters(in: .whitespaces)
        if c == "`", info.contains("`") { return nil }
        return (String(run), info, indent)
    }

    private static func isFenceClose(_ line: String, fence: String) -> Bool {
        guard line.leadingSpaces < 4 else { return false }
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let c = fence.first, t.count >= fence.count else { return false }
        return t.allSatisfy { $0 == c }
    }

    private static func atxHeading(_ line: String) -> (Int, String)? {
        guard line.leadingSpaces < 4 else { return nil }
        let t = line.trimmingCharacters(in: .whitespaces)
        let hashes = t.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = t.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // Optional closing sequence
        if let r = text.range(of: #"(^|\s)#+$"#, options: .regularExpression) {
            text = String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return (hashes, text)
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        guard line.leadingSpaces < 4 else { return false }
        let chars = line.filter { $0 != " " }
        guard chars.count >= 3, let c = chars.first, "-*_".contains(c) else { return false }
        return chars.allSatisfy { $0 == c }
    }

    private static func isHTMLBlockStart(_ trimmed: String) -> Bool {
        matches(trimmed, #"^</?(address|article|aside|blockquote|body|center|details|dialog|div|dl|fieldset|figcaption|figure|footer|form|h[1-6]|header|hr|html|iframe|img|li|main|nav|ol|p|picture|pre|section|summary|table|tbody|td|tfoot|th|thead|tr|ul|video|audio|br|a)(\s|/?>|$)"#, ignoreCase: true)
            || trimmed.hasPrefix("<!--")
    }

    /// Whether a line would start a non-paragraph block (used to stop lazy continuation).
    private static func startsBlock(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return fenceOpen(line) != nil || atxHeading(line) != nil || isThematicBreak(line)
            || (line.leadingSpaces < 4 && t.hasPrefix(">")) || listMarker(line) != nil
    }

    private static func tableAlignments(_ line: String) -> [String?]? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), matches(t, #"^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?$"#) else { return nil }
        guard t.contains("|") else { return nil }
        return splitRow(t).map { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            switch (c.hasPrefix(":"), c.hasSuffix(":")) {
            case (true, true): return "center"
            case (true, false): return "left"
            case (false, true): return "right"
            default: return nil
            }
        }
    }

    private static func splitRow(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
        var cells: [String] = []
        var cell = ""
        var inCode = false
        var prev: Character = " "
        for ch in t {
            if ch == "`" { inCode.toggle() }
            if ch == "|" && prev != "\\" && !inCode {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else if ch == "|" && prev == "\\" {
                cell.removeLast()
                cell.append("|")
            } else {
                cell.append(ch)
            }
            prev = ch
        }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    // MARK: - Inline

    func renderInline(_ text: String) -> String {
        let chars = Array(text)
        return renderInline(chars, 0, chars.count)
    }

    private func renderInline(_ s: [Character], _ from: Int, _ to: Int) -> String {
        var out = ""
        var i = from

        while i < to {
            let c = s[i]

            // Backslash escapes & hard break
            if c == "\\", i + 1 < to {
                let n = s[i + 1]
                if n == "\n" { out += "<br>\n"; i += 2; continue }
                if n.isASCII, n.isPunctuation || n.isSymbol {
                    out += escape(String(n)); i += 2; continue
                }
            }

            // Hard break: two+ spaces before newline
            if c == " ", let nl = indexAfterSpaces(s, i, to), nl < to, s[nl] == "\n", nl - i >= 2 {
                out += "<br>\n"; i = nl + 1; continue
            }

            // Code span
            if c == "`" {
                var run = 0
                while i + run < to, s[i + run] == "`" { run += 1 }
                if let close = findBacktickRun(s, i + run, to, run) {
                    var code = String(s[(i + run)..<close]).replacingOccurrences(of: "\n", with: " ")
                    if code.count >= 2, code.hasPrefix(" "), code.hasSuffix(" "),
                       code.contains(where: { $0 != " " }) {
                        code = String(code.dropFirst().dropLast())
                    }
                    out += "<code>\(escape(code))</code>"
                    i = close + run
                    continue
                }
                out += String(repeating: "`", count: run)
                i += run
                continue
            }

            // Autolink <url> / inline HTML
            if c == "<" {
                if let end = indexOf(">", s, i + 1, to) {
                    let inner = String(s[(i + 1)..<end])
                    if Self.matches(inner, #"^[a-zA-Z][a-zA-Z0-9+.-]{1,31}:[^\s<>]*$"#) {
                        out += "<a href=\"\(escapeAttr(inner))\">\(escape(inner))</a>"
                        i = end + 1; continue
                    }
                    if Self.matches(inner, #"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*$"#) {
                        out += "<a href=\"mailto:\(escapeAttr(inner))\">\(escape(inner))</a>"
                        i = end + 1; continue
                    }
                    if Self.matches(inner, #"^(/?[a-zA-Z][a-zA-Z0-9-]*(\s[^<>]*)?/?|!--[\s\S]*--)$"#) {
                        out += "<" + inner + ">"
                        i = end + 1; continue
                    }
                }
            }

            // Images & links
            if c == "!" || c == "[", let (html, next) = parseLinkOrImage(s, i, to) {
                out += html
                i = next
                continue
            }

            // Bare URL autolinks (GFM)
            if c == "h" || c == "w", i == from || !(s[i - 1].isLetter || s[i - 1].isNumber),
               let (html, next) = parseBareURL(s, i, to) {
                out += html
                i = next
                continue
            }

            // Emphasis / strong / strikethrough
            if c == "*" || c == "_" || c == "~" {
                if let (html, next) = parseEmphasis(s, i, to) {
                    out += html
                    i = next
                    continue
                }
                var run = 0
                while i + run < to, s[i + run] == c { run += 1 }
                out += String(repeating: c, count: run)
                i += run
                continue
            }

            if c == "&" {
                // Keep valid entities, escape bare ampersands
                if let end = indexOf(";", s, i + 1, min(to, i + 32)),
                   Self.matches(String(s[i...end]), #"^&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z][a-zA-Z0-9]{1,31});$"#) {
                    out += String(s[i...end]); i = end + 1; continue
                }
                out += "&amp;"; i += 1; continue
            }

            out += escape(String(c))
            i += 1
        }
        return out
    }

    private func indexAfterSpaces(_ s: [Character], _ i: Int, _ to: Int) -> Int? {
        var k = i
        while k < to, s[k] == " " { k += 1 }
        return k
    }

    private func indexOf(_ ch: Character, _ s: [Character], _ from: Int, _ to: Int) -> Int? {
        var k = from
        while k < to { if s[k] == ch { return k }; k += 1 }
        return nil
    }

    private func findBacktickRun(_ s: [Character], _ from: Int, _ to: Int, _ len: Int) -> Int? {
        var k = from
        while k < to {
            if s[k] == "`" {
                var run = 0
                while k + run < to, s[k + run] == "`" { run += 1 }
                if run == len { return k }
                k += run
            } else {
                k += 1
            }
        }
        return nil
    }

    /// Finds the matching `]` for a `[` at `open`, honouring nesting, escapes and code spans.
    private func matchingBracket(_ s: [Character], _ open: Int, _ to: Int) -> Int? {
        var depth = 0
        var k = open
        while k < to {
            switch s[k] {
            case "\\": k += 1
            case "`":
                var run = 0
                while k + run < to, s[k + run] == "`" { run += 1 }
                if let close = findBacktickRun(s, k + run, to, run) { k = close + run - 1 } else { k += run - 1 }
            case "[": depth += 1
            case "]":
                depth -= 1
                if depth == 0 { return k }
            default: break
            }
            k += 1
        }
        return nil
    }

    private func parseLinkOrImage(_ s: [Character], _ i: Int, _ to: Int) -> (String, Int)? {
        let isImage = s[i] == "!"
        let open = isImage ? i + 1 : i
        guard open < to, s[open] == "[", let close = matchingBracket(s, open, to) else { return nil }
        let label = String(s[(open + 1)..<close])
        if label.hasPrefix("^") { return nil } // footnote ref: leave as text

        var url: String?
        var title: String?
        var next = close + 1

        if next < to, s[next] == "(" {
            // Inline destination
            var depth = 0
            var k = next
            var end: Int?
            while k < to {
                if s[k] == "\\" { k += 2; continue }
                if s[k] == "(" { depth += 1 }
                if s[k] == ")" { depth -= 1; if depth == 0 { end = k; break } }
                k += 1
            }
            guard let e = end else { return nil }
            let inner = String(s[(next + 1)..<e]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let m = Self.firstMatch(inner, #"^<([^>]*)>(?:\s+(?:"(.*)"|'(.*)'|\((.*)\)))?$"#)
                ?? Self.firstMatch(inner, #"^(\S*)(?:\s+(?:"(.*)"|'(.*)'|\((.*)\)))?$"#) {
                url = m[1]
                title = [m[2], m[3], m[4]].first(where: { !$0.isEmpty })
            } else {
                return nil
            }
            next = e + 1
        } else {
            // Reference: [text][ref], [text][], [text]
            var ref = label
            if next < to, s[next] == "[", let rclose = indexOf("]", s, next + 1, to) {
                let r = String(s[(next + 1)..<rclose])
                if !r.isEmpty { ref = r }
                next = rclose + 1
            }
            let key = ref.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
            guard let def = references[key] else { return nil }
            url = def.url
            title = def.title
        }

        guard var dest = url else { return nil }
        dest = unescapeBackslashes(dest)
        let titleAttr = title.map { " title=\"\(escapeAttr(unescapeBackslashes($0)))\"" } ?? ""

        if isImage {
            let alt = Self.stripTags(renderInline(label))
            let src = imageResolver?(dest) ?? dest
            return ("<img src=\"\(escapeAttr(src))\" alt=\"\(escapeAttr(alt))\"\(titleAttr)>", next)
        }
        let labelChars = Array(label)
        let text = renderInline(labelChars, 0, labelChars.count)
        return ("<a href=\"\(escapeAttr(dest))\"\(titleAttr)>\(text)</a>", next)
    }

    private func parseBareURL(_ s: [Character], _ i: Int, _ to: Int) -> (String, Int)? {
        let rest = String(s[i..<min(to, i + 2048)])
        guard rest.hasPrefix("http://") || rest.hasPrefix("https://") || rest.hasPrefix("www."),
              let m = Self.firstMatch(rest, #"^(?:https?://|www\.)[^\s<]*"#) else { return nil }
        var url = m[0]
        // Trim trailing punctuation, and unbalanced closing parens
        while let last = url.last, "?!.,:*_~'\";".contains(last) { url.removeLast() }
        while url.hasSuffix(")"), url.filter({ $0 == ")" }).count > url.filter({ $0 == "(" }).count { url.removeLast() }
        guard url.count > 7 else { return nil }
        let href = url.hasPrefix("www.") ? "http://" + url : url
        return ("<a href=\"\(escapeAttr(href))\">\(escape(url))</a>", i + url.count)
    }

    private func parseEmphasis(_ s: [Character], _ i: Int, _ to: Int) -> (String, Int)? {
        let c = s[i]
        var run = 0
        while i + run < to, s[i + run] == c { run += 1 }

        if c == "~" {
            guard run == 2 || run == 1 else { return nil }
            guard let close = findCloser(s, i + run, to, c, run) else { return nil }
            return ("<del>\(renderInline(s, i + run, close))</del>", close + run)
        }

        // Opener must be left-flanking
        let after = i + run < to ? s[i + run] : " "
        guard !after.isWhitespace else { return nil }
        if c == "_", i > 0, s[i - 1].isLetter || s[i - 1].isNumber { return nil }

        // Only a closing run of the same length matches; otherwise the run stays literal.
        let len = min(run, 3)
        guard run == len, let close = findCloser(s, i + len, to, c, len) else { return nil }
        let inner = renderInline(s, i + len, close)
        switch len {
        case 3: return ("<em><strong>\(inner)</strong></em>", close + len)
        case 2: return ("<strong>\(inner)</strong>", close + len)
        default: return ("<em>\(inner)</em>", close + len)
        }
    }

    /// Finds a closing delimiter run of exactly `len` chars `c`, skipping code spans and links.
    private func findCloser(_ s: [Character], _ from: Int, _ to: Int, _ c: Character, _ len: Int) -> Int? {
        var k = from
        while k < to {
            let ch = s[k]
            if ch == "\\" { k += 2; continue }
            if ch == "`" {
                var run = 0
                while k + run < to, s[k + run] == "`" { run += 1 }
                if let close = findBacktickRun(s, k + run, to, run) { k = close + run } else { k += run }
                continue
            }
            if ch == "[", let close = matchingBracket(s, k, to) {
                // Skip over link text but not destination; emphasis may wrap whole links
                k = close + 1
                continue
            }
            if ch == c {
                var run = 0
                while k + run < to, s[k + run] == c { run += 1 }
                let before = s[k - 1]
                let afterIdx = k + run
                let rightFlanking = !before.isWhitespace
                let wordAfter = afterIdx < to && (s[afterIdx].isLetter || s[afterIdx].isNumber)
                if rightFlanking, k > from {
                    if run == len, !(c == "_" && wordAfter) { return k }
                    // A longer run can close a shorter opener (e.g. ***a** b* is rare; keep simple)
                    if run > len, len < 3, run == 3, !(c == "_" && wordAfter) { return k + (run - len) }
                }
                k += run
                continue
            }
            k += 1
        }
        return nil
    }

    // MARK: - Utilities

    private func unescapeBackslashes(_ s: String) -> String {
        var out = ""
        var escaped = false
        for ch in s {
            if escaped { out.append(ch); escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            out.append(ch)
        }
        if escaped { out.append("\\") }
        return out
    }

    static func slug(_ html: String) -> String {
        let text = stripTags(html).lowercased()
        var out = ""
        for ch in text {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" { out.append(ch) }
            else if ch == " " { out.append("-") }
        }
        return out
    }

    static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private static var regexCache = [String: NSRegularExpression]()
    private static let regexLock = NSLock()

    private static func regex(_ pattern: String, ignoreCase: Bool) -> NSRegularExpression {
        let key = (ignoreCase ? "i:" : "s:") + pattern
        regexLock.lock(); defer { regexLock.unlock() }
        if let r = regexCache[key] { return r }
        let r = try! NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
        regexCache[key] = r
        return r
    }

    static func matches(_ s: String, _ pattern: String, ignoreCase: Bool = false) -> Bool {
        regex(pattern, ignoreCase: ignoreCase)
            .firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    /// Returns capture groups (index 0 = whole match); missing groups are "".
    static func firstMatch(_ s: String, _ pattern: String, ignoreCase: Bool = false) -> [String]? {
        let ns = s as NSString
        guard let m = regex(pattern, ignoreCase: ignoreCase)
            .firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map {
            m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0))
        }
    }
}

func escape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for ch in s {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        default: out.append(ch)
        }
    }
    return out
}

func escapeAttr(_ s: String) -> String {
    escape(s).replacingOccurrences(of: "\"", with: "&quot;")
}

extension String {
    var leadingSpaces: Int { prefix(while: { $0 == " " }).count }

    func trimmingLeadingSpaces() -> String { String(drop(while: { $0 == " " })) }

    func removingLeadingSpaces(upTo n: Int) -> String {
        String(dropFirst(min(n, leadingSpaces)))
    }
}
