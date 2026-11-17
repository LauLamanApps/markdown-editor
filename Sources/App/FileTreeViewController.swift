import Cocoa
import CoreServices

/// Sidebar with the files of a folder, Sublime Text style. Markdown files open
/// in the editor (as a new tab), other files open in their default app and can
/// be dragged into the editor to insert a link.
final class FileTreeViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    final class Node {
        let url: URL
        let isDirectory: Bool
        private(set) var loadedChildren: [Node]?

        init(url: URL, isDirectory: Bool) {
            self.url = url
            self.isDirectory = isDirectory
        }

        var children: [Node] {
            if let loadedChildren { return loadedChildren }
            let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            let nodes = urls.compactMap { u -> Node? in
                let values = try? u.resourceValues(forKeys: Set(keys))
                let dir = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
                return Node(url: u, isDirectory: dir)
            }.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
            loadedChildren = nodes
            return nodes
        }

        func reload() { loadedChildren = nil }
    }

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"]

    /// Called when a Markdown file is chosen; the controller opens it.
    var openMarkdown: (URL) -> Void = { _ in }

    private(set) var root: Node?
    private let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private let header = NSTextField(labelWithString: "")
    private let emptyState = NSStackView()
    private var stream: FSEventStreamRef?
    private var selectedURL: URL?

    override func loadView() {
        let container = NSView()

        let column = NSTableColumn(identifier: .init("name"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.floatsGroupRows = false
        outline.autoresizesOutlineColumn = true
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(rowClicked)
        outline.doubleAction = #selector(rowDoubleClicked)
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        outline.setDraggingSourceOperationMask(.copy, forLocal: true)
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu

        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        header.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.lineBreakMode = .byTruncatingMiddle

        let hint = NSTextField(wrappingLabelWithString: "Open a folder to browse its files.")
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        let button = NSButton(title: "Open Folder…", target: self, action: #selector(chooseFolder(_:)))
        emptyState.orientation = .vertical
        emptyState.spacing = 10
        emptyState.addArrangedSubview(hint)
        emptyState.addArrangedSubview(button)

        for v in [header, scroll, emptyState] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emptyState.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            emptyState.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            emptyState.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])
        view = container
        updateEmptyState()
    }

    deinit { stopWatching() }

    // MARK: Root folder

    func setRoot(_ url: URL?) {
        guard url?.standardizedFileURL != root?.url.standardizedFileURL else { return }
        stopWatching()
        root = url.map { Node(url: $0.standardizedFileURL, isDirectory: true) }
        header.stringValue = root?.url.lastPathComponent.uppercased() ?? ""
        header.toolTip = root?.url.path
        outline.reloadData()
        updateEmptyState()
        if let url { startWatching(url) }
        if let selectedURL { reveal(selectedURL) }
    }

    @objc func chooseFolder(_ sender: Any?) {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open"
        panel.directoryURL = root?.url
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.setRoot(url)
        }
    }

    private func updateEmptyState() {
        guard isViewLoaded else { return }
        emptyState.isHidden = root != nil
        scroll.isHidden = root == nil
        header.isHidden = root == nil
    }

    /// Selects `url` in the tree, expanding its parent folders.
    func reveal(_ url: URL) {
        selectedURL = url.standardizedFileURL
        guard isViewLoaded, let root else { return }
        let target = url.standardizedFileURL.pathComponents
        let base = root.url.pathComponents
        guard target.count > base.count, Array(target.prefix(base.count)) == base else {
            outline.deselectAll(nil)
            return
        }
        var node = root
        for component in target[base.count...] {
            guard let next = node.children.first(where: { $0.url.lastPathComponent == component }) else { return }
            if next.isDirectory { outline.expandItem(next) }
            node = next
        }
        let row = outline.row(forItem: node)
        if row >= 0 {
            outline.selectRowIndexes([row], byExtendingSelection: false)
            outline.scrollRowToVisible(row)
        }
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        ((item as? Node) ?? root)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? Node) ?? root)!.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.isDirectory ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        (item as? Node)?.url as NSURL?
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let image = NSImageView()
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingMiddle
            for v in [image, text] as [NSView] {
                v.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(v)
            }
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            cell.imageView = image
            cell.textField = text
            return cell
        }()
        let isMarkdown = Self.markdownExtensions.contains(node.url.pathExtension.lowercased())
        cell.textField?.stringValue = node.url.lastPathComponent
        cell.textField?.textColor = node.isDirectory || isMarkdown ? .labelColor : .secondaryLabelColor
        let symbol = node.isDirectory ? "folder" : (isMarkdown ? "doc.text" : "doc")
        cell.imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        cell.imageView?.contentTintColor = node.isDirectory ? .controlAccentColor : .secondaryLabelColor
        return cell
    }

    // MARK: Actions

    private var clickedNode: Node? {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        return row >= 0 ? outline.item(atRow: row) as? Node : nil
    }

    @objc private func rowClicked() {
        guard let node = clickedNode, !node.isDirectory,
              Self.markdownExtensions.contains(node.url.pathExtension.lowercased()) else { return }
        openMarkdown(node.url)
    }

    @objc private func rowDoubleClicked() {
        guard let node = clickedNode else { return }
        if node.isDirectory {
            outline.isItemExpanded(node) ? outline.collapseItem(node) : outline.expandItem(node)
        } else if !Self.markdownExtensions.contains(node.url.pathExtension.lowercased()) {
            NSWorkspace.shared.open(node.url)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let node = outline.clickedRow >= 0 ? outline.item(atRow: outline.clickedRow) as? Node : nil
        menu.addItem(withTitle: "New Markdown File", action: #selector(newFile(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "New Folder", action: #selector(newFolder(_:)), keyEquivalent: "").target = self
        if node != nil {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Show in Finder", action: #selector(showInFinder(_:)), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Move to Trash", action: #selector(moveToTrash(_:)), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Folder…", action: #selector(chooseFolder(_:)), keyEquivalent: "").target = self
    }

    /// Folder for new items: the clicked folder, the clicked file's folder, or the root.
    private var targetFolder: URL? {
        let node = outline.clickedRow >= 0 ? outline.item(atRow: outline.clickedRow) as? Node : nil
        guard let node else { return root?.url }
        return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
    }

    private func uniqueURL(in folder: URL, base: String, ext: String?) -> URL {
        var n = 1
        while true {
            let name = n == 1 ? base : "\(base) \(n)"
            let url = ext.map { folder.appendingPathComponent(name).appendingPathExtension($0) } ?? folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }

    @objc private func newFile(_ sender: Any?) {
        guard let folder = targetFolder else { return }
        let url = uniqueURL(in: folder, base: "Untitled", ext: "md")
        do {
            try Data().write(to: url)
            refresh()
            reveal(url)
            openMarkdown(url)
        } catch { presentError(error) }
    }

    @objc private func newFolder(_ sender: Any?) {
        guard let folder = targetFolder else { return }
        do {
            try FileManager.default.createDirectory(at: uniqueURL(in: folder, base: "New Folder", ext: nil),
                                                    withIntermediateDirectories: false)
            refresh()
        } catch { presentError(error) }
    }

    @objc private func showInFinder(_ sender: Any?) {
        guard let node = clickedNode else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    @objc private func moveToTrash(_ sender: Any?) {
        guard let node = clickedNode else { return }
        NSWorkspace.shared.recycle([node.url]) { [weak self] _, error in
            if let error { self?.presentError(error) }
            self?.refresh()
        }
    }

    // MARK: Watching for changes

    /// Reloads the tree, keeping expanded folders and the selection.
    func refresh() {
        guard let root else { return }
        let expanded = (0..<outline.numberOfRows).compactMap { outline.item(atRow: $0) as? Node }
            .filter { outline.isItemExpanded($0) }.map(\.url)
        func reset(_ node: Node) {
            guard node.isDirectory, node.loadedChildren != nil else { return }
            node.loadedChildren?.forEach(reset)
            node.reload()
        }
        reset(root)
        outline.reloadData()
        for url in expanded.sorted(by: { $0.pathComponents.count < $1.pathComponents.count }) {
            if let node = find(url) { outline.expandItem(node) }
        }
        if let selectedURL { reveal(selectedURL) }
    }

    private func find(_ url: URL) -> Node? {
        guard let root else { return nil }
        let target = url.pathComponents
        let base = root.url.pathComponents
        guard target.count > base.count else { return nil }
        var node = root
        for component in target[base.count...] {
            guard let next = node.children.first(where: { $0.url.lastPathComponent == component }) else { return nil }
            node = next
        }
        return node
    }

    private func startWatching(_ url: URL) {
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let controller = Unmanaged<FileTreeViewController>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { controller.refresh() }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, [url.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func stopWatching() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
