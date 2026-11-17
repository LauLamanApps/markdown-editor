import Cocoa
import WebKit

/// Editor window: plain-text Markdown on the left, live preview on the right.
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, WKNavigationDelegate {
    enum Layout: Int { case editor, split, preview }

    private static let layoutKey = "Layout"
    private static let fontSizeKey = "EditorFontSize"
    private static let defaultFontSize: CGFloat = 14

    private let textView: NSTextView
    private let editorScroll: NSScrollView
    private let webView: WKWebView
    private let split = NSSplitViewController()
    private let highlighter: MarkdownHighlighter

    private var pageLoaded = false
    private var pendingRender: DispatchWorkItem?
    private var scrollFraction: CGFloat = 0

    var currentText: String { textView.string }

    init(text: String) {
        let size = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        highlighter = MarkdownHighlighter(fontSize: size > 0 ? CGFloat(size) : Self.defaultFontSize)

        editorScroll = NSTextView.scrollableTextView()
        textView = editorScroll.documentView as! NSTextView
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 480, height: 300)
        window.tabbingMode = .preferred
        super.init(window: window)

        configureTextView(text)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground") // no white flash in dark mode

        let editorVC = NSViewController()
        editorVC.view = editorScroll
        let previewVC = NSViewController()
        previewVC.view = webView
        let editorItem = NSSplitViewItem(viewController: editorVC)
        let previewItem = NSSplitViewItem(viewController: previewVC)
        editorItem.canCollapse = true
        previewItem.canCollapse = true
        editorItem.minimumThickness = 240
        previewItem.minimumThickness = 240
        split.addSplitViewItem(editorItem)
        split.addSplitViewItem(previewItem)
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        split.splitView.autosaveName = "EditorSplit"

        window.contentViewController = split
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.delegate = self
        window.setFrameAutosaveName("EditorWindow")

        apply(Layout(rawValue: UserDefaults.standard.integer(forKey: Self.layoutKey)) ?? .split)
        loadPage()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.makeFirstResponder(textView)
    }

    override var document: AnyObject? {
        didSet { documentLocationChanged() }
    }

    // MARK: Text view

    private func configureTextView(_ text: String) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.delegate = self
        textView.textStorage?.delegate = highlighter
        textView.font = highlighter.baseFont
        textView.typingAttributes = highlighter.baseAttributes
        textView.string = text
        highlighter.highlight(textView.textStorage!)

        editorScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(editorDidScroll),
                                               name: NSView.boundsDidChangeNotification, object: editorScroll.contentView)
    }

    /// Replaces all text (used by revert and external changes), keeping the cursor where possible.
    func replaceText(_ text: String) {
        guard text != textView.string else { return }
        let selection = textView.selectedRange()
        textView.string = text
        highlighter.highlight(textView.textStorage!)
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        scheduleRender(delay: 0)
    }

    func textDidChange(_ notification: Notification) {
        scheduleRender(delay: 0.15)
    }

    @objc private func editorDidScroll() {
        guard let doc = editorScroll.documentView else { return }
        let visible = editorScroll.contentView.bounds
        let scrollable = doc.frame.height - visible.height
        scrollFraction = scrollable > 0 ? min(max(visible.minY / scrollable, 0), 1) : 0
        syncPreviewScroll()
    }

    // MARK: Preview

    static func renderPage(_ markdown: String, documentURL: URL?, title: String) -> String {
        HTMLDocument.wrap(body: renderBody(markdown, documentURL: documentURL), title: title)
    }

    private static func renderBody(_ markdown: String, documentURL: URL?) -> String {
        let base = documentURL?.deletingLastPathComponent()
        var renderer = MarkdownRenderer(imageResolver: { src in
            base.flatMap { ImageInliner.dataURI(for: src, relativeTo: $0) }
        })
        return renderer.render(markdown)
    }

    private var documentURL: URL? { (document as? NSDocument)?.fileURL }

    func documentLocationChanged() {
        // Relative links and images resolve against the file's folder
        guard isWindowLoaded || window != nil else { return }
        loadPage()
    }

    private func loadPage() {
        pageLoaded = false
        let title = (document as? NSDocument)?.displayName ?? "Untitled"
        let html = Self.renderPage(textView.string, documentURL: documentURL, title: title)
        webView.loadHTMLString(html, baseURL: documentURL?.deletingLastPathComponent())
    }

    private func scheduleRender(delay: TimeInterval) {
        pendingRender?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updatePreview() }
        pendingRender = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func updatePreview() {
        guard pageLoaded else { loadPage(); return }
        let body = Self.renderBody(textView.string, documentURL: documentURL)
        guard let json = try? JSONSerialization.data(withJSONObject: [body]),
              let literal = String(data: json, encoding: .utf8) else { return }
        // Swap the body in place so the preview keeps its scroll position
        webView.evaluateJavaScript("document.querySelector('.markdown-body').innerHTML = \(literal)[0];")
    }

    private func syncPreviewScroll() {
        guard pageLoaded, layout == .split else { return }
        webView.evaluateJavaScript(
            "window.scrollTo(0, (document.documentElement.scrollHeight - window.innerHeight) * \(scrollFraction));")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        syncPreviewScroll()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)

        // In-page anchors
        if let fragment = url.fragment, var base = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            base.fragment = nil
            let current = webView.url.flatMap { u -> URL? in
                var c = URLComponents(url: u, resolvingAgainstBaseURL: false); c?.fragment = nil; return c?.url
            }
            if base.url == current || url.scheme == "about" {
                let id = fragment.replacingOccurrences(of: "'", with: "\\'")
                webView.evaluateJavaScript("document.getElementById(decodeURIComponent('\(id)'))?.scrollIntoView()")
                return
            }
        }
        // Links to other Markdown files open in this app
        if url.isFileURL, ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"].contains(url.pathExtension.lowercased()) {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc func printPreview(_ sender: Any?) {
        guard let window else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        let op = webView.printOperation(with: info)
        op.view?.frame = webView.bounds
        op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: Layout

    private var layout: Layout {
        let items = split.splitViewItems
        if items[0].isCollapsed { return .preview }
        if items[1].isCollapsed { return .editor }
        return .split
    }

    private func apply(_ layout: Layout) {
        let items = split.splitViewItems
        items[0].isCollapsed = layout == .preview
        items[1].isCollapsed = layout == .editor
        if layout == .preview {
            window?.makeFirstResponder(webView)
        } else {
            window?.makeFirstResponder(textView)
        }
    }

    @objc func setLayout(_ sender: NSMenuItem) {
        guard let layout = Layout(rawValue: sender.tag) else { return }
        apply(layout)
        UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutKey)
    }

    // MARK: Font size

    private func setFontSize(_ size: CGFloat) {
        let clamped = min(max(size, 9), 36)
        highlighter.fontSize = clamped
        textView.font = highlighter.baseFont
        textView.typingAttributes = highlighter.baseAttributes
        highlighter.highlight(textView.textStorage!)
        UserDefaults.standard.set(Double(clamped), forKey: Self.fontSizeKey)
    }

    @objc func makeTextBigger(_ sender: Any?) { setFontSize(highlighter.fontSize + 1) }
    @objc func makeTextSmaller(_ sender: Any?) { setFontSize(highlighter.fontSize - 1) }
    @objc func makeTextActualSize(_ sender: Any?) { setFontSize(Self.defaultFontSize) }

    // MARK: Formatting

    @objc func toggleBold(_ sender: Any?) { toggleWrap("**") }
    @objc func toggleItalic(_ sender: Any?) { toggleWrap("_") }
    @objc func toggleStrikethrough(_ sender: Any?) { toggleWrap("~~") }
    @objc func toggleCode(_ sender: Any?) { toggleWrap("`") }

    @objc func insertLink(_ sender: Any?) {
        let range = textView.selectedRange()
        let selected = (textView.string as NSString).substring(with: range)
        if selected.hasPrefix("http://") || selected.hasPrefix("https://") {
            replace(range, with: "[](\(selected))", select: NSRange(location: range.location + 1, length: 0))
        } else {
            let label = selected.isEmpty ? "link" : selected
            let urlStart = range.location + (label as NSString).length + 3
            replace(range, with: "[\(label)](https://)", select: NSRange(location: urlStart, length: 8))
        }
    }

    @objc func setHeading(_ sender: NSMenuItem) {
        let level = sender.tag
        transformLines { line in
            let stripped = line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            return level == 0 ? stripped : String(repeating: "#", count: level) + " " + stripped
        }
    }

    @objc func toggleBulletList(_ sender: Any?) { toggleLinePrefix("- ", pattern: #"^(\s*)[-*+]\s+"#) }
    @objc func toggleQuote(_ sender: Any?) { toggleLinePrefix("> ", pattern: #"^(\s*)>\s?"#) }

    /// Wraps the selection in `marker`, or removes it when the selection is already wrapped.
    private func toggleWrap(_ marker: String) {
        let ns = textView.string as NSString
        let range = textView.selectedRange()
        let m = (marker as NSString).length
        let selected = ns.substring(with: range)

        if range.location >= m, NSMaxRange(range) + m <= ns.length,
           ns.substring(with: NSRange(location: range.location - m, length: m)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(range), length: m)) == marker {
            let outer = NSRange(location: range.location - m, length: range.length + 2 * m)
            replace(outer, with: selected, select: NSRange(location: outer.location, length: range.length))
            return
        }
        if selected.count > 2 * marker.count, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
            replace(range, with: inner, select: NSRange(location: range.location, length: (inner as NSString).length))
            return
        }
        replace(range, with: marker + selected + marker, select: NSRange(location: range.location + m, length: range.length))
    }

    private func toggleLinePrefix(_ prefix: String, pattern: String) {
        let ns = textView.string as NSString
        let lines = ns.substring(with: ns.lineRange(for: textView.selectedRange()))
            .components(separatedBy: "\n").filter { !$0.isEmpty }
        let allPrefixed = !lines.isEmpty && lines.allSatisfy { $0.range(of: pattern, options: .regularExpression) != nil }
        transformLines { line in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            return allPrefixed
                ? line.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
                : prefix + line
        }
    }

    /// Applies `transform` to every line touched by the selection.
    private func transformLines(_ transform: (String) -> String) {
        let ns = textView.string as NSString
        let lineRange = ns.lineRange(for: textView.selectedRange())
        let original = ns.substring(with: lineRange)
        let hasNewline = original.hasSuffix("\n")
        var lines = original.components(separatedBy: "\n")
        if hasNewline { lines.removeLast() }
        let result = lines.map(transform).joined(separator: "\n") + (hasNewline ? "\n" : "")
        let length = (result as NSString).length - (hasNewline ? 1 : 0)
        replace(lineRange, with: result, select: NSRange(location: lineRange.location, length: length))
    }

    /// Text change that goes through the undo manager.
    private func replace(_ range: NSRange, with string: String, select: NSRange) {
        guard textView.shouldChangeText(in: range, replacementString: string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: highlighter.baseAttributes))
        textView.didChangeText()
        textView.setSelectedRange(select)
    }

    // MARK: Menu state

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(setLayout(_:)) {
            item.state = item.tag == layout.rawValue ? .on : .off
            return true
        }
        let formatting: [Selector] = [#selector(toggleBold(_:)), #selector(toggleItalic(_:)), #selector(toggleStrikethrough(_:)),
                                      #selector(toggleCode(_:)), #selector(insertLink(_:)), #selector(setHeading(_:)),
                                      #selector(toggleBulletList(_:)), #selector(toggleQuote(_:))]
        if let action = item.action, formatting.contains(action) {
            return layout != .preview
        }
        return true
    }
}
