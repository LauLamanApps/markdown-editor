import Cocoa
import UniformTypeIdentifiers
import WebKit

/// Editor window: Markdown source on the left, live preview on the right,
/// formatting toolbar on top and a status bar under the editor.
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate,
                                    WKNavigationDelegate, NSToolbarDelegate, NSToolbarItemValidation {
    enum Layout: Int { case editor, split, preview }

    private let textView: MarkdownTextView
    private let editorScroll = NSScrollView()
    private let editorContainer = NSView()
    private let statusBar = NSVisualEffectView()
    private let statusLeft = NSTextField(labelWithString: "")
    private let statusRight = NSTextField(labelWithString: "")
    private let webView: WKWebView
    private let split = NSSplitViewController()
    private let highlighter = MarkdownHighlighter()
    private var layoutGroup: NSToolbarItemGroup?

    private var pageLoaded = false
    private var loadedTheme: PreviewTheme?
    private var renderedOptions: MarkdownOptions?
    private var pendingRender: DispatchWorkItem?
    private var pendingStatus: DispatchWorkItem?
    private var scrollFraction: CGFloat = 0
    private var appliedEditorSettings: [AnyHashable] = []

    var currentText: String { textView.string }

    init(text: String) {
        textView = MarkdownTextView(usingTextLayoutManager: true)
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(WebResourceHandler(), forURLScheme: WebResourceHandler.scheme)
        webView = WKWebView(frame: .zero, configuration: config)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 520, height: 320)
        window.tabbingMode = .preferred
        // Title on its own row, so the toolbar starts at the leading edge
        window.toolbarStyle = .expanded
        super.init(window: window)

        buildEditor(text)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground") // no white flash in dark mode

        let editorVC = NSViewController()
        editorVC.view = editorContainer
        let previewVC = NSViewController()
        previewVC.view = webView
        let editorItem = NSSplitViewItem(viewController: editorVC)
        let previewItem = NSSplitViewItem(viewController: previewVC)
        for item in [editorItem, previewItem] {
            item.canCollapse = true
            item.minimumThickness = 260
        }
        split.addSplitViewItem(editorItem)
        split.addSplitViewItem(previewItem)
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        split.splitView.autosaveName = "EditorSplit"

        window.contentViewController = split
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.delegate = self
        window.setFrameAutosaveName("EditorWindow")

        let toolbar = NSToolbar(identifier: "EditorToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window.toolbar = toolbar

        applySettings()
        apply(Layout(rawValue: UserDefaults.standard.integer(forKey: AppSettings.Key.layout)) ?? .split, focus: true)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var document: AnyObject? {
        didSet { documentLocationChanged() }
    }

    private var documentURL: URL? { (document as? NSDocument)?.fileURL }

    // MARK: Editor

    private func buildEditor(_ text: String) {
        editorScroll.hasVerticalScroller = true
        editorScroll.autohidesScrollers = true
        editorScroll.borderType = .noBorder
        editorScroll.drawsBackground = true

        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 600)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
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
        textView.drawsBackground = true
        textView.delegate = self
        textView.textStorage?.delegate = highlighter
        textView.documentDirectory = { [weak self] in self?.documentURL?.deletingLastPathComponent() }
        textView.string = text
        editorScroll.documentView = textView

        editorScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(editorDidScroll),
                                               name: NSView.boundsDidChangeNotification, object: editorScroll.contentView)
        editorScroll.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(updateTextInsets),
                                               name: NSView.frameDidChangeNotification, object: editorScroll)

        // Status bar: counts on the left, cursor position on the right
        statusBar.material = .titlebar
        statusBar.blendingMode = .withinWindow
        for label in [statusLeft, statusRight] {
            label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            statusBar.addSubview(label)
        }
        let divider = NSBox()
        divider.boxType = .separator
        for view in [editorScroll, statusBar, divider] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            editorContainer.addSubview(view)
        }
        NSLayoutConstraint.activate([
            editorScroll.topAnchor.constraint(equalTo: editorContainer.topAnchor),
            editorScroll.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            editorScroll.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            editorScroll.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            divider.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),
            statusLeft.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 12),
            statusLeft.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            statusRight.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -12),
            statusRight.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            statusRight.leadingAnchor.constraint(greaterThanOrEqualTo: statusLeft.trailingAnchor, constant: 12),
        ])
        statusLeft.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLeft.lineBreakMode = .byTruncatingTail
    }

    /// Replaces all text (revert, external change), keeping the cursor where possible.
    func replaceText(_ text: String) {
        guard text != textView.string else { return }
        let selection = textView.selectedRange()
        textView.string = text
        highlighter.highlight(textView.textStorage!)
        textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        scheduleRender(delay: 0)
        scheduleStatus()
    }

    func textDidChange(_ notification: Notification) {
        scheduleRender(delay: 0.15)
        scheduleStatus()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        scheduleStatus(delay: 0.05)
    }

    @objc private func editorDidScroll() {
        guard let doc = editorScroll.documentView else { return }
        let visible = editorScroll.contentView.bounds
        let scrollable = doc.frame.height - visible.height
        scrollFraction = scrollable > 0 ? min(max(visible.minY / scrollable, 0), 1) : 0
        syncPreviewScroll()
    }

    /// Centres the text in a readable column when the window is wide.
    @objc private func updateTextInsets() {
        var horizontal: CGFloat = 24
        if AppSettings.readableWidth {
            let charWidth = ("0" as NSString).size(withAttributes: [.font: highlighter.baseFont]).width
            let column = charWidth * CGFloat(AppSettings.lineLength)
            horizontal = max(24, (editorScroll.contentSize.width - column) / 2)
        }
        let inset = NSSize(width: horizontal, height: 24)
        if textView.textContainerInset != inset { textView.textContainerInset = inset }
    }

    private func scheduleStatus(delay: TimeInterval = 0.3) {
        pendingStatus?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateStatus() }
        pendingStatus = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func updateStatus() {
        let text = textView.string
        let ns = text as NSString
        var words = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            words += 1
        }
        let characters = text.count
        let minutes = max(1, Int((Double(words) / 220).rounded()))
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        func n(_ v: Int) -> String { nf.string(from: NSNumber(value: v)) ?? "\(v)" }
        statusLeft.stringValue = "\(n(words)) \(words == 1 ? "word" : "words") · \(n(characters)) characters · \(minutes) min read"

        let sel = textView.selectedRange()
        let location = min(sel.location, ns.length)
        var line = 1
        ns.enumerateSubstrings(in: NSRange(location: 0, length: location), options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
            if NSMaxRange(enclosing) <= location { line += 1 }
        }
        if location > 0, location == ns.length, !text.hasSuffix("\n") { line = max(1, line - 1) }
        let lineStart = ns.lineRange(for: NSRange(location: location, length: 0)).location
        var right = "Ln \(line), Col \(location - lineStart + 1)"
        if sel.length > 0 { right = "\(n(sel.length)) selected · " + right }
        statusRight.stringValue = right
    }

    // MARK: Settings

    @objc private func settingsChanged() {
        DispatchQueue.main.async { [weak self] in self?.applySettings() }
    }

    private func applySettings() {
        let theme = AppSettings.editorTheme
        let font = AppSettings.editorFont
        let editorState: [AnyHashable] = [theme.rawValue, font.fontName, font.pointSize, AppSettings.lineSpacing,
                                          AppSettings.readableWidth, AppSettings.lineLength]
        if editorState != appliedEditorSettings {
            appliedEditorSettings = editorState
            highlighter.configure(font: font, theme: theme, lineSpacing: AppSettings.lineSpacing)
            let p = highlighter.palette
            editorContainer.appearance = theme.appearance
            textView.backgroundColor = p.background
            editorScroll.backgroundColor = p.background
            textView.insertionPointColor = p.cursor
            textView.selectedTextAttributes = [.backgroundColor: p.selection]
            textView.font = font
            textView.typingAttributes = highlighter.baseAttributes
            highlighter.highlight(textView.textStorage!)
            updateTextInsets()
        }
        statusBar.isHidden = !AppSettings.statusBar
        webView.appearance = AppSettings.previewAppearance.nsAppearance

        if loadedTheme != AppSettings.previewTheme {
            loadPage()
        } else if renderedOptions != AppSettings.markdownOptions {
            scheduleRender(delay: 0)
        }
        scheduleStatus(delay: 0)
    }

    // MARK: Preview

    private static func renderBody(_ markdown: String, documentURL: URL?, options: MarkdownOptions) -> String {
        let base = documentURL?.deletingLastPathComponent()
        var renderer = MarkdownRenderer(options: options, imageResolver: { src in
            base.flatMap { ImageInliner.dataURI(for: src, relativeTo: $0) }
        })
        return renderer.render(markdown)
    }

    func documentLocationChanged() {
        // Relative links and images resolve against the file's folder
        guard window != nil else { return }
        loadPage()
    }

    private func loadPage() {
        pageLoaded = false
        let theme = AppSettings.previewTheme
        let options = AppSettings.markdownOptions
        loadedTheme = theme
        renderedOptions = options
        let title = (document as? NSDocument)?.displayName ?? "Untitled"
        let body = Self.renderBody(textView.string, documentURL: documentURL, options: options)
        let html = HTMLDocument.wrap(body: body, title: title, theme: theme, head: WebResourceHandler.previewHead)
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
        let options = AppSettings.markdownOptions
        renderedOptions = options
        let body = Self.renderBody(textView.string, documentURL: documentURL, options: options)
        guard let json = try? JSONSerialization.data(withJSONObject: [body]),
              let literal = String(data: json, encoding: .utf8) else { return }
        // Swap the body in place so the preview keeps its scroll position
        webView.evaluateJavaScript("MDP.update(\(literal)[0]);")
    }

    private func syncPreviewScroll() {
        guard pageLoaded, AppSettings.syncScroll, layout == .split else { return }
        webView.evaluateJavaScript("MDP.scrollToFraction(\(scrollFraction));")
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

        // In-page anchors (table of contents, footnotes)
        if let fragment = url.fragment {
            var target = URLComponents(url: url, resolvingAgainstBaseURL: false)
            target?.fragment = nil
            var current = webView.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            current?.fragment = nil
            if target?.url == current?.url || url.scheme == "about" {
                let id = fragment.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                webView.evaluateJavaScript("document.getElementById(decodeURIComponent('\(id)'))?.scrollIntoView({behavior: 'smooth'})")
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

    // MARK: Export

    /// The preview as currently shown, with highlighted code and rendered math and diagrams.
    private func renderedPage(_ completion: @escaping (String) -> Void) {
        webView.evaluateJavaScript("MDP.renderedHTML()") { [weak self] result, _ in
            guard let self else { return }
            let body = result as? String
                ?? Self.renderBody(self.textView.string, documentURL: self.documentURL, options: AppSettings.markdownOptions)
            var head = ""
            if body.contains("class=\"katex") {
                // KaTeX output needs its stylesheet and fonts
                head = "<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.css\">"
            }
            let title = (self.document as? NSDocument)?.displayName ?? "Untitled"
            completion(HTMLDocument.wrap(body: body, title: title, theme: AppSettings.previewTheme, head: head))
        }
    }

    private var exportBaseName: String {
        documentURL?.deletingPathExtension().lastPathComponent ?? (document as? NSDocument)?.displayName ?? "Untitled"
    }

    @objc func exportHTML(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = exportBaseName + ".html"
        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let url = panel.url else { return }
            renderedPage { html in
                do { try Data(html.utf8).write(to: url, options: .atomic) } catch { self.presentError(error) }
            }
        }
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = exportBaseName + ".pdf"
        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let url = panel.url else { return }
            let info = printInfo()
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            let op = webView.printOperation(with: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = true
            op.view?.frame = webView.bounds
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
    }

    @objc func copyHTML(_ sender: Any?) {
        webView.evaluateJavaScript("MDP.renderedHTML()") { [weak self] result, _ in
            guard let self else { return }
            let html = result as? String
                ?? Self.renderBody(self.textView.string, documentURL: self.documentURL, options: AppSettings.markdownOptions)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(html, forType: .string)
            pb.setString(html, forType: .html)
        }
    }

    @objc func printPreview(_ sender: Any?) {
        guard let window else { return }
        let op = webView.printOperation(with: printInfo())
        op.view?.frame = webView.bounds
        op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    private func printInfo() -> NSPrintInfo {
        let info = (NSPrintInfo.shared.copy() as! NSPrintInfo)
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        return info
    }

    // MARK: Layout

    private var layout: Layout {
        let items = split.splitViewItems
        if items[0].isCollapsed { return .preview }
        if items[1].isCollapsed { return .editor }
        return .split
    }

    private func apply(_ layout: Layout, focus: Bool) {
        let items = split.splitViewItems
        items[0].isCollapsed = layout == .preview
        items[1].isCollapsed = layout == .editor
        layoutGroup?.selectedIndex = layout.rawValue
        if focus { window?.makeFirstResponder(layout == .preview ? webView : textView) }
        if layout == .split { syncPreviewScroll() }
    }

    @objc func setLayout(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSToolbarItemGroup)?.selectedIndex ?? Layout.split.rawValue
        guard let layout = Layout(rawValue: tag) else { return }
        apply(layout, focus: true)
        UserDefaults.standard.set(layout.rawValue, forKey: AppSettings.Key.layout)
    }

    // MARK: Font size

    @objc func makeTextBigger(_ sender: Any?) { AppSettings.fontSize += 1 }
    @objc func makeTextSmaller(_ sender: Any?) { AppSettings.fontSize -= 1 }
    @objc func makeTextActualSize(_ sender: Any?) { AppSettings.fontSize = AppSettings.defaultFontSize }

    // MARK: Formatting

    @objc func toggleBold(_ sender: Any?) { toggleWrap("**") }
    @objc func toggleItalic(_ sender: Any?) { toggleWrap("_") }
    @objc func toggleStrikethrough(_ sender: Any?) { toggleWrap("~~") }
    @objc func toggleHighlight(_ sender: Any?) { toggleWrap("==") }
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

    @objc func insertImage(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.directoryURL = documentURL?.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK else { return }
            let links = panel.urls.map(textView.markdownLink(for:)).joined(separator: "\n")
            replace(textView.selectedRange(), with: links,
                    select: NSRange(location: textView.selectedRange().location + (links as NSString).length, length: 0))
        }
    }

    @objc func insertTable(_ sender: Any?) {
        let table = "| Column | Column |\n| ------ | ------ |\n| Cell   | Cell   |\n"
        let range = textView.selectedRange()
        let ns = textView.string as NSString
        let atLineStart = range.location == 0 || ns.substring(with: NSRange(location: range.location - 1, length: 1)) == "\n"
        let text = (atLineStart ? "" : "\n\n") + table
        let first = range.location + (text as NSString).length - (table as NSString).length + 2
        replace(range, with: text, select: NSRange(location: first, length: 6))
    }

    @objc func setHeading(_ sender: Any?) {
        let level = (sender as? NSMenuItem)?.tag ?? 0
        transformLines { line in
            let stripped = line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            return level == 0 ? stripped : String(repeating: "#", count: level) + " " + stripped
        }
    }

    @objc func toggleBulletList(_ sender: Any?) { toggleLinePrefix(pattern: #"^(\s*)[-*+]\s+(?!\[[ xX]\])"#) { _ in "- " } }
    @objc func toggleNumberedList(_ sender: Any?) { toggleLinePrefix(pattern: #"^(\s*)\d+[.)]\s+"#) { "\($0 + 1). " } }
    @objc func toggleTaskList(_ sender: Any?) { toggleLinePrefix(pattern: #"^(\s*)[-*+]\s+\[[ xX]\]\s+"#) { _ in "- [ ] " } }
    @objc func toggleQuote(_ sender: Any?) { toggleLinePrefix(pattern: #"^(\s*)>\s?"#) { _ in "> " } }
    @objc func indentLines(_ sender: Any?) { textView.shiftLines(by: 1) }
    @objc func outdentLines(_ sender: Any?) { textView.shiftLines(by: -1) }

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

    /// Adds a prefix to every selected line, or removes it when all lines already have one.
    private func toggleLinePrefix(pattern: String, prefix: (Int) -> String) {
        let ns = textView.string as NSString
        let lines = ns.substring(with: ns.lineRange(for: textView.selectedRange()))
            .components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allPrefixed = !lines.isEmpty && lines.allSatisfy { $0.range(of: pattern, options: .regularExpression) != nil }
        var index = 0
        transformLines { line in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            if allPrefixed {
                return line.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
            }
            // Replace another list marker instead of stacking prefixes
            let bare = line.replacingOccurrences(of: #"^(\s*)(?:[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+|>\s?)"#,
                                                 with: "$1", options: .regularExpression)
            let indent = String(bare.prefix(while: { $0 == " " || $0 == "\t" }))
            defer { index += 1 }
            return indent + prefix(index) + bare.dropFirst(indent.count)
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
        window?.makeFirstResponder(textView)
    }

    // MARK: Validation

    private static let editingActions: Set<Selector> = [
        #selector(toggleBold(_:)), #selector(toggleItalic(_:)), #selector(toggleStrikethrough(_:)),
        #selector(toggleHighlight(_:)), #selector(toggleCode(_:)), #selector(insertLink(_:)),
        #selector(insertImage(_:)), #selector(insertTable(_:)), #selector(setHeading(_:)),
        #selector(toggleBulletList(_:)), #selector(toggleNumberedList(_:)), #selector(toggleTaskList(_:)),
        #selector(toggleQuote(_:)), #selector(indentLines(_:)), #selector(outdentLines(_:)),
    ]

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(setLayout(_:)) {
            item.state = item.tag == layout.rawValue ? .on : .off
            return true
        }
        if let action = item.action, Self.editingActions.contains(action) { return layout != .preview }
        return true
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if let action = item.action, Self.editingActions.contains(action) { return layout != .preview }
        return true
    }

    // MARK: Toolbar

    private enum ToolbarID {
        static let layout = NSToolbarItem.Identifier("layout")
        static let bold = NSToolbarItem.Identifier("bold")
        static let italic = NSToolbarItem.Identifier("italic")
        static let strikethrough = NSToolbarItem.Identifier("strikethrough")
        static let heading = NSToolbarItem.Identifier("heading")
        static let bulletList = NSToolbarItem.Identifier("bulletList")
        static let numberedList = NSToolbarItem.Identifier("numberedList")
        static let taskList = NSToolbarItem.Identifier("taskList")
        static let quote = NSToolbarItem.Identifier("quote")
        static let code = NSToolbarItem.Identifier("code")
        static let link = NSToolbarItem.Identifier("link")
        static let image = NSToolbarItem.Identifier("image")
        static let table = NSToolbarItem.Identifier("table")
        static let export = NSToolbarItem.Identifier("export")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.bold, ToolbarID.italic, ToolbarID.strikethrough, ToolbarID.heading, .space,
         ToolbarID.bulletList, ToolbarID.numberedList, ToolbarID.taskList, ToolbarID.quote, .space,
         ToolbarID.code, ToolbarID.link, ToolbarID.image, ToolbarID.table,
         .flexibleSpace, ToolbarID.layout, ToolbarID.export]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func button(_ label: String, _ symbol: String, _ action: Selector) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = label
            item.paletteLabel = label
            item.toolTip = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            item.action = action
            item.isBordered = true
            return item
        }

        switch id {
        case ToolbarID.bold: return button("Bold", "bold", #selector(toggleBold(_:)))
        case ToolbarID.italic: return button("Italic", "italic", #selector(toggleItalic(_:)))
        case ToolbarID.strikethrough: return button("Strikethrough", "strikethrough", #selector(toggleStrikethrough(_:)))
        case ToolbarID.bulletList: return button("Bulleted List", "list.bullet", #selector(toggleBulletList(_:)))
        case ToolbarID.numberedList: return button("Numbered List", "list.number", #selector(toggleNumberedList(_:)))
        case ToolbarID.taskList: return button("Task List", "checklist", #selector(toggleTaskList(_:)))
        case ToolbarID.quote: return button("Quote", "text.quote", #selector(toggleQuote(_:)))
        case ToolbarID.code: return button("Code", "chevron.left.forwardslash.chevron.right", #selector(toggleCode(_:)))
        case ToolbarID.link: return button("Link", "link", #selector(insertLink(_:)))
        case ToolbarID.image: return button("Image", "photo", #selector(insertImage(_:)))
        case ToolbarID.table: return button("Table", "tablecells", #selector(insertTable(_:)))

        case ToolbarID.heading:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "Heading"
            item.paletteLabel = "Heading"
            item.toolTip = "Heading"
            item.image = NSImage(systemSymbolName: "textformat.size", accessibilityDescription: "Heading")
            let menu = NSMenu()
            for level in 1...6 {
                let entry = menu.addItem(withTitle: "Heading \(level)", action: #selector(setHeading(_:)), keyEquivalent: "")
                entry.tag = level
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "Body Text", action: #selector(setHeading(_:)), keyEquivalent: "").tag = 0
            item.menu = menu
            item.showsIndicator = true
            return item

        case ToolbarID.export:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "Export"
            item.paletteLabel = "Export"
            item.toolTip = "Export"
            item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Export")
            let menu = NSMenu()
            menu.addItem(withTitle: "Export as HTML…", action: #selector(exportHTML(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Export as PDF…", action: #selector(exportPDF(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Copy HTML", action: #selector(copyHTML(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Print…", action: #selector(printPreview(_:)), keyEquivalent: "")
            item.menu = menu
            item.showsIndicator = false
            return item

        case ToolbarID.layout:
            let images = ["doc.plaintext", "rectangle.split.2x1", "eye"].map {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil)!
            }
            let group = NSToolbarItemGroup(itemIdentifier: id, images: images, selectionMode: .selectOne,
                                           labels: ["Editor", "Split", "Preview"], target: self, action: #selector(setLayout(_:)))
            group.label = "Layout"
            group.paletteLabel = "Layout"
            group.selectedIndex = layout.rawValue
            layoutGroup = group
            return group

        default:
            return nil
        }
    }
}
