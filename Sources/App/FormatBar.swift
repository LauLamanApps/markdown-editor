import Cocoa

/// Formatting buttons above the editor. Lives inside the editor pane so it
/// follows the pane's width; buttons that don't fit move into a » menu.
/// Actions go up the responder chain to the editor window controller.
final class FormatBar: NSView {
    struct Entry {
        let title: String
        let symbol: String
        let action: Selector?
        var menu: [(title: String, action: Selector, tag: Int)] = []
        var isSeparator: Bool { action == nil && menu.isEmpty }
        static let separator = Entry(title: "", symbol: "", action: nil)
    }

    private var entries: [Entry] = []
    private var views: [NSView] = []
    private let overflow = NSPopUpButton(frame: .zero, pullsDown: true)
    private let divider = NSBox()

    private let buttonSize = NSSize(width: 28, height: 24)
    private let separatorWidth: CGFloat = 13
    private let inset: CGFloat = 10

    init(entries: [Entry]) {
        super.init(frame: .zero)
        self.entries = entries
        views = entries.map(makeView)
        views.forEach(addSubview)

        overflow.bezelStyle = .accessoryBarAction
        overflow.isBordered = false
        (overflow.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        overflow.imagePosition = .imageOnly
        overflow.toolTip = "More"
        addSubview(overflow)

        divider.boxType = .separator
        addSubview(divider)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 36) }

    private func makeView(_ entry: Entry) -> NSView {
        if entry.isSeparator {
            let box = NSBox()
            box.boxType = .separator
            return box
        }
        let image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: entry.title)
        if !entry.menu.isEmpty {
            let popup = NSPopUpButton(frame: .zero, pullsDown: true)
            popup.bezelStyle = .accessoryBarAction
            popup.isBordered = false
            popup.toolTip = entry.title
            let head = NSMenuItem()
            head.image = image
            popup.menu?.addItem(head)
            for item in entry.menu {
                popup.menu?.addItem(withTitle: item.title, action: item.action, keyEquivalent: "").tag = item.tag
            }
            popup.refusesFirstResponder = true
            return popup
        }
        let button = NSButton(image: image ?? NSImage(), target: nil, action: entry.action)
        button.bezelStyle = .accessoryBarAction
        button.showsBorderOnlyWhileMouseInside = true
        button.toolTip = entry.title
        button.refusesFirstResponder = true
        return button
    }

    private func width(of entry: Entry) -> CGFloat {
        entry.isSeparator ? separatorWidth : (entry.menu.isEmpty ? buttonSize.width : buttonSize.width + 8)
    }

    override func layout() {
        super.layout()
        divider.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
        let y = (bounds.height - buttonSize.height) / 2
        let total = entries.map(width(of:)).reduce(0, +)
        let fitsAll = total + 2 * inset <= bounds.width
        let available = bounds.width - 2 * inset - (fitsAll ? 0 : buttonSize.width + 4)

        var x = inset
        var hidden: [Entry] = []
        for (entry, view) in zip(entries, views) {
            let w = width(of: entry)
            if hidden.isEmpty, x + w <= inset + available {
                view.isHidden = false
                let height = entry.isSeparator ? 16 : buttonSize.height
                view.frame = NSRect(x: x + (entry.isSeparator ? 6 : 0), y: (bounds.height - height) / 2,
                                    width: entry.isSeparator ? 1 : w, height: height)
                x += w
            } else {
                view.isHidden = true
                hidden.append(entry)
            }
        }
        // A separator at the edge looks odd
        if let last = views.indices.last(where: { !views[$0].isHidden }), entries[last].isSeparator {
            views[last].isHidden = true
        }

        overflow.isHidden = hidden.allSatisfy(\.isSeparator)
        guard !overflow.isHidden else { return }
        overflow.frame = NSRect(x: bounds.width - inset - buttonSize.width, y: y, width: buttonSize.width, height: buttonSize.height)
        let menu = NSMenu()
        let head = NSMenuItem()
        head.image = NSImage(systemSymbolName: "chevron.forward.2", accessibilityDescription: "More")
        menu.addItem(head)
        for entry in hidden {
            if entry.isSeparator {
                if menu.items.count > 1, menu.items.last?.isSeparatorItem == false { menu.addItem(.separator()) }
            } else if entry.menu.isEmpty {
                let item = menu.addItem(withTitle: entry.title, action: entry.action, keyEquivalent: "")
                item.image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)
            } else {
                let item = menu.addItem(withTitle: entry.title, action: nil, keyEquivalent: "")
                item.image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)
                let sub = NSMenu()
                for m in entry.menu { sub.addItem(withTitle: m.title, action: m.action, keyEquivalent: "").tag = m.tag }
                item.submenu = sub
            }
        }
        if menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        overflow.menu = menu
    }
}
