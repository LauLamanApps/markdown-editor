import Cocoa

/// Host app. Its only job is to carry the Quick Look extension; launching it
/// once registers the extension and shows a short how-to.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 230),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "Markdown Preview"
        window.center()

        let title = NSTextField(labelWithString: "Markdown Preview is installed")
        title.font = .boldSystemFont(ofSize: 17)

        let body = NSTextField(wrappingLabelWithString:
            "Select a .md file in Finder and press Space to see it formatted.\n\n" +
            "If you still see plain text, enable “Markdown Preview” under " +
            "System Settings → General → Login Items & Extensions → Quick Look.")
        body.preferredMaxLayoutWidth = 400

        let settings = NSButton(title: "Open Extension Settings", target: self, action: #selector(openSettings))
        let quit = NSButton(title: "Done", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.keyEquivalent = "\r"

        let buttons = NSStackView(views: [settings, quit])
        let stack = NSStackView(views: [title, body, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        window.contentView = stack

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
