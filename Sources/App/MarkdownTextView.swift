import Cocoa

/// Text view with Markdown editing behaviour: list continuation, list
/// indenting with Tab, auto-closing brackets and quotes, and Markdown links
/// for dropped files and pasted images.
final class MarkdownTextView: NSTextView {
    /// Folder of the document, for relative links. Nil while untitled.
    var documentDirectory: () -> URL? = { nil }

    private var ns: NSString { string as NSString }

    // MARK: Lists

    private static let listItem = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:([-*+])|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?"#)
    private static let quoteLine = try! NSRegularExpression(pattern: #"^([ \t]*)(>[ \t]?)+"#)

    override func insertNewline(_ sender: Any?) {
        guard AppSettings.continueLists, !hasMarkedText(), selectedRange().length == 0 else {
            super.insertNewline(sender)
            return
        }
        let cursor = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
        let lineEnd = lineRange.location + (ns.substring(with: lineRange).hasSuffix("\n") ? lineRange.length - 1 : lineRange.length)
        let line = ns.substring(with: NSRange(location: lineRange.location, length: lineEnd - lineRange.location))
        let lineNS = line as NSString
        let full = NSRange(location: 0, length: lineNS.length)

        var prefix: String?
        var nextPrefix = ""
        if let m = Self.listItem.firstMatch(in: line, range: full) {
            prefix = lineNS.substring(with: m.range)
            let indent = lineNS.substring(with: m.range(at: 1))
            let space = lineNS.substring(with: m.range(at: 5))
            let task = m.range(at: 6).location != NSNotFound ? "[ ] " : ""
            if m.range(at: 2).location != NSNotFound {
                nextPrefix = indent + lineNS.substring(with: m.range(at: 2)) + space + task
            } else {
                let n = (Int(lineNS.substring(with: m.range(at: 3))) ?? 0) + 1
                nextPrefix = indent + "\(n)" + lineNS.substring(with: m.range(at: 4)) + space + task
            }
        } else if let m = Self.quoteLine.firstMatch(in: line, range: full) {
            prefix = lineNS.substring(with: m.range)
            nextPrefix = prefix!.hasSuffix(" ") ? prefix! : prefix! + " "
        }

        guard let prefix, cursor >= lineRange.location + (prefix as NSString).length else {
            super.insertNewline(sender)
            return
        }

        if line.trimmingCharacters(in: .whitespaces) == prefix.trimmingCharacters(in: .whitespaces) {
            // Enter on an empty item ends the list
            let markerRange = NSRange(location: lineRange.location, length: (line as NSString).length)
            replace(markerRange, with: "", cursorAt: lineRange.location)
            return
        }
        insertText("\n" + nextPrefix, replacementRange: selectedRange())
    }

    // MARK: Indenting

    private var indentUnit: String {
        AppSettings.spacesForTab ? String(repeating: " ", count: AppSettings.tabWidth) : "\t"
    }

    private var selectionCoversLines: Bool {
        let sel = selectedRange()
        return sel.length > 0 && ns.substring(with: sel).contains("\n")
    }

    private func isListLine(at location: Int) -> Bool {
        let line = ns.substring(with: ns.lineRange(for: NSRange(location: location, length: 0)))
        return Self.listItem.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    override func insertTab(_ sender: Any?) {
        guard !hasMarkedText() else { super.insertTab(sender); return }
        if selectionCoversLines || isListLine(at: selectedRange().location) {
            shiftLines(by: 1)
        } else if AppSettings.spacesForTab {
            let lineStart = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0)).location
            let column = selectedRange().location - lineStart
            let width = AppSettings.tabWidth
            insertText(String(repeating: " ", count: width - column % width), replacementRange: selectedRange())
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        shiftLines(by: -1)
    }

    /// Indents (+1) or outdents (-1) every line touched by the selection.
    func shiftLines(by direction: Int) {
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: sel)
        let text = ns.substring(with: lineRange)
        let hasNewline = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")
        if hasNewline { lines.removeLast() }

        var firstDelta = 0
        for (k, line) in lines.enumerated() {
            var newLine = line
            if direction > 0 {
                if !line.isEmpty { newLine = indentUnit + line }
            } else if line.hasPrefix("\t") {
                newLine = String(line.dropFirst())
            } else {
                let spaces = min(line.prefix(while: { $0 == " " }).count, AppSettings.tabWidth)
                newLine = String(line.dropFirst(spaces))
            }
            let delta = (newLine as NSString).length - (line as NSString).length
            if k == 0 { firstDelta = delta }
            lines[k] = newLine
        }
        let result = lines.joined(separator: "\n") + (hasNewline ? "\n" : "")
        guard result != text, shouldChangeText(in: lineRange, replacementString: result) else { return }
        textStorage?.replaceCharacters(in: lineRange, with: result)
        didChangeText()
        if sel.length == 0 {
            setSelectedRange(NSRange(location: max(lineRange.location, sel.location + firstDelta), length: 0))
        } else {
            setSelectedRange(NSRange(location: lineRange.location, length: (result as NSString).length - (hasNewline ? 1 : 0)))
        }
    }

    // MARK: Auto-pairing

    private static let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "`": "`"]
    private static let wrapOnly: [String: String] = ["*": "*", "_": "_", "~": "~", "=": "="]
    private static let closers: Set<String> = [")", "]", "}", "\"", "`"]

    private func character(at location: Int) -> String? {
        guard location >= 0, location < ns.length else { return nil }
        return ns.substring(with: NSRange(location: location, length: 1))
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let typed = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""
        let sel = selectedRange()
        guard AppSettings.autoPair, !hasMarkedText(), (typed as NSString).length == 1,
              replacementRange.location == NSNotFound || replacementRange == sel else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        let next = character(at: sel.location + sel.length)
        let prev = character(at: sel.location - 1)

        // Typing a closer that is already there just steps over it
        if sel.length == 0, Self.closers.contains(typed), next == typed {
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            return
        }

        if let close = Self.pairs[typed] ?? (sel.length > 0 ? Self.wrapOnly[typed] : nil) {
            if sel.length > 0 {
                let inner = ns.substring(with: sel)
                super.insertText(typed + inner + close, replacementRange: sel)
                setSelectedRange(NSRange(location: sel.location + 1, length: sel.length))
                return
            }
            let nextIsOpen = next == nil || next!.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
                || Self.closers.contains(next!) || next == "," || next == "." || next == ";" || next == ":"
            let isQuote = typed == "\"" || typed == "`"
            let prevIsWord = prev.map { $0.rangeOfCharacter(from: .alphanumerics) != nil } ?? false
            if nextIsOpen && !(isQuote && prevIsWord) {
                super.insertText(typed + close, replacementRange: sel)
                setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                return
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if AppSettings.autoPair, sel.length == 0, let prev = character(at: sel.location - 1),
           let close = Self.pairs[prev], character(at: sel.location) == close {
            replace(NSRange(location: sel.location - 1, length: 2), with: "", cursorAt: sel.location - 1)
            return
        }
        super.deleteBackward(sender)
    }

    // MARK: Files and images

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        let index = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
        let links = urls.map(markdownLink(for:)).joined(separator: "\n")
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: index, length: 0))
        insertText(links, replacementRange: NSRange(location: index, length: 0))
        return true
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        guard pb.string(forType: .string) == nil, pb.availableType(from: [.fileURL]) == nil,
              let image = NSImage(pasteboard: pb) else {
            super.paste(sender)
            return
        }
        guard let dir = documentDirectory() else {
            let alert = NSAlert()
            alert.messageText = "Save the document first"
            alert.informativeText = "Pasted images are stored in an “images” folder next to the document."
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { NSSound.beep(); return }
        let folder = dir.appendingPathComponent("images", isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let file = folder.appendingPathComponent("pasted-\(formatter.string(from: Date())).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: file)
            insertText(markdownLink(for: file), replacementRange: selectedRange())
        } catch {
            presentError(error)
        }
    }

    func markdownLink(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let target = documentDirectory().map { Self.relativePath(from: $0, to: url) } ?? url.path
        let destination = target.contains(" ") ? "<\(target)>" : target
        let isImage = ["png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "tiff", "bmp"].contains(url.pathExtension.lowercased())
        return isImage ? "![\(name)](\(destination))" : "[\(name)](\(destination))"
    }

    static func relativePath(from dir: URL, to file: URL) -> String {
        let base = dir.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let target = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        var common = 0
        while common < min(base.count, target.count), base[common] == target[common] { common += 1 }
        guard common > 1 else { return file.path } // nothing shared but "/"
        let ups = Array(repeating: "..", count: base.count - common)
        return (ups + target[common...]).joined(separator: "/")
    }

    // MARK: Helpers

    private func replace(_ range: NSRange, with string: String, cursorAt location: Int) {
        guard shouldChangeText(in: range, replacementString: string) else { return }
        textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: typingAttributes))
        didChangeText()
        setSelectedRange(NSRange(location: location, length: 0))
    }
}
