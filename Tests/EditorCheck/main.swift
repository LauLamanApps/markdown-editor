import Cocoa

// Exercises the editor's typing behaviour (list continuation, indenting,
// auto-pairing) on a real MarkdownTextView. "|" marks the cursor.

AppSettings.register()
var failures = 0

func check(_ name: String, _ before: String, _ expected: String, _ action: (MarkdownTextView) -> Void) {
    let tv = MarkdownTextView(usingTextLayoutManager: true)
    tv.isRichText = false
    tv.allowsUndo = true
    let cursor = (before as NSString).range(of: "|")
    tv.string = before.replacingOccurrences(of: "|", with: "")
    tv.setSelectedRange(NSRange(location: cursor.location, length: 0))
    action(tv)
    let ns = tv.string as NSString
    let result = ns.replacingCharacters(in: NSRange(location: tv.selectedRange().location, length: 0), with: "|")
    if result == expected {
        print("✓ \(name)")
    } else {
        print("✗ \(name)\n  expected: \(expected.debugDescription)\n  got:      \(result.debugDescription)")
        failures += 1
    }
}

check("continue bullet", "- one|", "- one\n- |") { $0.insertNewline(nil) }
check("continue numbered", "1. one|", "1. one\n2. |") { $0.insertNewline(nil) }
check("continue task", "- [x] done|", "- [x] done\n- [ ] |") { $0.insertNewline(nil) }
check("continue nested", "  * deep|", "  * deep\n  * |") { $0.insertNewline(nil) }
check("continue quote", "> said|", "> said\n> |") { $0.insertNewline(nil) }
check("end list on empty item", "- one\n- |", "- one\n|") { $0.insertNewline(nil) }
check("plain newline", "text|", "text\n|") { $0.insertNewline(nil) }
check("tab indents list item", "- it|em", "    - it|em") { $0.insertTab(nil) }
check("backtab outdents", "    - it|em", "- it|em") { $0.insertBacktab(nil) }
check("tab inserts spaces", "ab|", "ab  |") { $0.insertTab(nil) }
check("pair bracket", "a |", "a (|)") { $0.insertText("(", replacementRange: NSRange(location: NSNotFound, length: 0)) }
check("step over closer", "(a|)", "(a)|") { $0.insertText(")", replacementRange: NSRange(location: NSNotFound, length: 0)) }
check("no pair before word", "|word", "(|word") { $0.insertText("(", replacementRange: NSRange(location: NSNotFound, length: 0)) }
check("no quote pair after word", "don|", "don\"|") { $0.insertText("\"", replacementRange: NSRange(location: NSNotFound, length: 0)) }
check("delete empty pair", "x(|)", "x|") { $0.deleteBackward(nil) }
check("wrap selection", "say |hi", "say *hi|*") { tv in
    tv.setSelectedRange(NSRange(location: 4, length: 2))
    tv.insertText("*", replacementRange: NSRange(location: NSNotFound, length: 0))
    tv.setSelectedRange(NSRange(location: NSMaxRange(tv.selectedRange()), length: 0))
}
check("relative path", "|", "../img/a b.png|") { tv in
    tv.insertText(MarkdownTextView.relativePath(from: URL(fileURLWithPath: "/tmp/x/docs"),
                                                to: URL(fileURLWithPath: "/tmp/x/img/a b.png")),
                  replacementRange: NSRange(location: NSNotFound, length: 0))
}

exit(failures == 0 ? 0 : 1)
