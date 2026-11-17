import Cocoa

/// The menu bar, built in code since the app has no nib.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        let appName = "Markdown Preview"

        // App
        let appMenu = submenu(of: main, title: appName)
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let services = appMenu.addItem(withTitle: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu()
        NSApp.servicesMenu = services.submenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File
        let file = submenu(of: main, title: "File")
        file.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        file.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        let recent = file.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        // Lets AppKit fill this menu with recent documents (normally set up by the nib)
        recentMenu.perform(NSSelectorFromString("_setMenuName:"), with: "NSRecentDocumentsMenu")
        recent.submenu = recentMenu
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: "Save…", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        file.addItem(withTitle: "Duplicate", action: #selector(NSDocument.duplicate(_:)), keyEquivalent: "S")
        file.addItem(withTitle: "Rename…", action: #selector(NSDocument.rename(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Move To…", action: #selector(NSDocument.move(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Revert To", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(withTitle: "Export as HTML…", action: #selector(MarkdownDocument.exportHTML(_:)), keyEquivalent: "e")
            .keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "Print…", action: #selector(EditorWindowController.printPreview(_:)), keyEquivalent: "p")

        // Edit
        let edit = submenu(of: main, title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = edit.addItem(withTitle: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        findItem(findMenu, "Find…", .showFindInterface, "f")
        findItem(findMenu, "Find and Replace…", .showReplaceInterface, "f", [.command, .option])
        findItem(findMenu, "Find Next", .nextMatch, "g")
        findItem(findMenu, "Find Previous", .previousMatch, "G")
        findItem(findMenu, "Use Selection for Find", .setSearchString, "e")
        find.submenu = findMenu

        // Format
        let format = submenu(of: main, title: "Format")
        format.addItem(withTitle: "Bold", action: #selector(EditorWindowController.toggleBold(_:)), keyEquivalent: "b")
        format.addItem(withTitle: "Italic", action: #selector(EditorWindowController.toggleItalic(_:)), keyEquivalent: "i")
        format.addItem(withTitle: "Strikethrough", action: #selector(EditorWindowController.toggleStrikethrough(_:)), keyEquivalent: "x")
            .keyEquivalentModifierMask = [.command, .shift]
        format.addItem(withTitle: "Inline Code", action: #selector(EditorWindowController.toggleCode(_:)), keyEquivalent: "k")
            .keyEquivalentModifierMask = [.command, .shift]
        format.addItem(withTitle: "Link", action: #selector(EditorWindowController.insertLink(_:)), keyEquivalent: "k")
        format.addItem(.separator())
        for level in 1...3 {
            let item = format.addItem(withTitle: "Heading \(level)", action: #selector(EditorWindowController.setHeading(_:)), keyEquivalent: "\(level)")
            item.keyEquivalentModifierMask = [.command, .option]
            item.tag = level
        }
        format.addItem(withTitle: "Body Text", action: #selector(EditorWindowController.setHeading(_:)), keyEquivalent: "0")
            .keyEquivalentModifierMask = [.command, .option]
        format.addItem(.separator())
        format.addItem(withTitle: "Bulleted List", action: #selector(EditorWindowController.toggleBulletList(_:)), keyEquivalent: "l")
            .keyEquivalentModifierMask = [.command, .shift]
        format.addItem(withTitle: "Quote", action: #selector(EditorWindowController.toggleQuote(_:)), keyEquivalent: "'")

        // View
        let view = submenu(of: main, title: "View")
        let modes: [(String, String)] = [("Editor Only", "1"), ("Editor and Preview", "2"), ("Preview Only", "3")]
        for (index, (title, key)) in modes.enumerated() {
            let item = view.addItem(withTitle: title, action: #selector(EditorWindowController.setLayout(_:)), keyEquivalent: key)
            item.tag = index
        }
        view.addItem(.separator())
        view.addItem(withTitle: "Bigger", action: #selector(EditorWindowController.makeTextBigger(_:)), keyEquivalent: "+")
        view.addItem(withTitle: "Smaller", action: #selector(EditorWindowController.makeTextSmaller(_:)), keyEquivalent: "-")
        view.addItem(withTitle: "Actual Size", action: #selector(EditorWindowController.makeTextActualSize(_:)), keyEquivalent: "0")
        view.addItem(.separator())
        view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]

        // Window
        let window = submenu(of: main, title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        // Help
        let help = submenu(of: main, title: "Help")
        help.addItem(withTitle: "Markdown Syntax Guide", action: #selector(AppDelegate.openMarkdownGuide(_:)), keyEquivalent: "")
        help.addItem(withTitle: "Quick Look Extension Settings…", action: #selector(AppDelegate.openQuickLookSettings(_:)), keyEquivalent: "")
        NSApp.helpMenu = help

        return main
    }

    private static func submenu(of main: NSMenu, title: String) -> NSMenu {
        let item = main.addItem(withTitle: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        return menu
    }

    private static func findItem(_ menu: NSMenu, _ title: String, _ action: NSTextFinder.Action,
                                 _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) {
        let item = menu.addItem(withTitle: title, action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: key)
        item.tag = action.rawValue
        item.keyEquivalentModifierMask = modifiers
    }
}
