import Cocoa

/// A Markdown file. The text view is the source of truth while a window is
/// open; `text` holds the contents before the window exists.
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    var text = ""

    private var editor: EditorWindowController? {
        windowControllers.first as? EditorWindowController
    }

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        addWindowController(EditorWindowController(text: text))
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        text = decoded
        // Revert / external change while the window is open
        editor?.replaceText(decoded)
    }

    override func data(ofType typeName: String) throws -> Data {
        var contents = editor?.currentText ?? text
        if AppSettings.trailingNewline, !contents.isEmpty, !contents.hasSuffix("\n") { contents += "\n" }
        return Data(contents.utf8)
    }

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        ["net.daringfireball.markdown"]
    }

    override var fileURL: URL? {
        didSet { editor?.documentLocationChanged() }
    }
}
