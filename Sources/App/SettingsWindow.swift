import Cocoa
import SwiftUI

/// Settings window with toolbar-style tabs, each a SwiftUI form bound to user defaults.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true

        func tab(_ title: String, _ symbol: String, _ view: some View) -> NSTabViewItem {
            let host = NSHostingController(rootView: view.frame(width: 480).fixedSize())
            host.sizingOptions = [.preferredContentSize]
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return item
        }
        tabs.addTabViewItem(tab("General", "gearshape", GeneralSettings()))
        tabs.addTabViewItem(tab("Editor", "character.cursor.ibeam", EditorSettings()))
        tabs.addTabViewItem(tab("Preview", "eye", PreviewSettings()))
        tabs.addTabViewItem(tab("Markdown", "text.badge.checkmark", MarkdownSettings()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.setFrameAutosaveName("Settings")
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct GeneralSettings: View {
    @AppStorage(AppSettings.Key.syncScroll) private var syncScroll = true
    @AppStorage(AppSettings.Key.statusBar) private var statusBar = true
    @AppStorage(AppSettings.Key.trailingNewline) private var trailingNewline = true

    var body: some View {
        Form {
            Section {
                Toggle("Scroll the preview along with the editor", isOn: $syncScroll)
                Toggle("Show word count and cursor position", isOn: $statusBar)
                Toggle("End files with a newline when saving", isOn: $trailingNewline)
            }
            Section("Quick Look") {
                HStack {
                    Text("Finder previews (Space) use the Preview and Markdown settings.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Extension Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct EditorSettings: View {
    @AppStorage(AppSettings.Key.editorTheme) private var theme = EditorTheme.system.rawValue
    @AppStorage(AppSettings.Key.editorFont) private var font = ""
    @AppStorage(AppSettings.Key.editorFontSize) private var fontSize = Double(AppSettings.defaultFontSize)
    @AppStorage(AppSettings.Key.lineSpacing) private var lineSpacing = 1.3
    @AppStorage(AppSettings.Key.readableWidth) private var readableWidth = true
    @AppStorage(AppSettings.Key.lineLength) private var lineLength = 90
    @AppStorage(AppSettings.Key.autoPair) private var autoPair = true
    @AppStorage(AppSettings.Key.continueLists) private var continueLists = true
    @AppStorage(AppSettings.Key.spacesForTab) private var spacesForTab = true
    @AppStorage(AppSettings.Key.tabWidth) private var tabWidth = 4

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(EditorTheme.allCases, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) }
                }
                Picker("Font", selection: $font) {
                    ForEach(EditorFonts.choices, id: \.name) { Text($0.label).tag($0.name) }
                }
                Stepper(value: $fontSize, in: 9...36, step: 1) {
                    LabeledContent("Size", value: "\(Int(fontSize)) pt")
                }
                LabeledContent("Line spacing") {
                    Slider(value: $lineSpacing, in: 1.0...2.0, step: 0.1) { EmptyView() }
                        .frame(width: 180)
                    Text(String(format: "%.1f", lineSpacing)).monospacedDigit().frame(width: 28)
                }
                Toggle("Limit line length", isOn: $readableWidth)
                if readableWidth {
                    Stepper(value: $lineLength, in: 50...160, step: 5) {
                        LabeledContent("Characters per line", value: "\(lineLength)")
                    }
                }
            }
            Section("Typing") {
                Toggle("Close brackets and quotes automatically", isOn: $autoPair)
                Toggle("Continue lists and quotes on Return", isOn: $continueLists)
                Toggle("Insert spaces for Tab", isOn: $spacesForTab)
                Picker("Tab width", selection: $tabWidth) {
                    Text("2").tag(2)
                    Text("4").tag(4)
                    Text("8").tag(8)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PreviewSettings: View {
    @AppStorage(AppSettings.Key.previewTheme) private var theme = PreviewTheme.github.rawValue
    @AppStorage(AppSettings.Key.previewAppearance) private var appearance = AppSettings.Appearance.system.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(PreviewTheme.allCases, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) }
                }
                Picker("Appearance", selection: $appearance) {
                    Text("Follow System").tag(AppSettings.Appearance.system.rawValue)
                    Text("Light").tag(AppSettings.Appearance.light.rawValue)
                    Text("Dark").tag(AppSettings.Appearance.dark.rawValue)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Exported HTML always follows the reader's light or dark mode.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct MarkdownSettings: View {
    @AppStorage(MarkdownOptions.Key.math) private var math = true
    @AppStorage(MarkdownOptions.Key.mermaid) private var mermaid = true
    @AppStorage(MarkdownOptions.Key.footnotes) private var footnotes = true
    @AppStorage(MarkdownOptions.Key.highlight) private var highlight = true
    @AppStorage(MarkdownOptions.Key.tableOfContents) private var toc = true
    @AppStorage(MarkdownOptions.Key.hardLineBreaks) private var hardLineBreaks = false
    @AppStorage(MarkdownOptions.Key.smartPunctuation) private var smartPunctuation = false
    @AppStorage(MarkdownOptions.Key.frontMatter) private var frontMatter = MarkdownOptions.FrontMatter.table.rawValue

    var body: some View {
        Form {
            Section("Extensions") {
                Toggle("TeX math: $inline$ and $$display$$", isOn: $math)
                Toggle("Mermaid diagrams in ```mermaid blocks", isOn: $mermaid)
                Toggle("Footnotes: [^1]", isOn: $footnotes)
                Toggle("Highlight: ==text==", isOn: $highlight)
                Toggle("Table of contents: [TOC]", isOn: $toc)
            }
            Section("Text") {
                Toggle("Treat single line breaks as breaks", isOn: $hardLineBreaks)
                Toggle("Smart quotes, dashes and ellipses", isOn: $smartPunctuation)
                Picker("Front matter", selection: $frontMatter) {
                    Text("Table").tag(MarkdownOptions.FrontMatter.table.rawValue)
                    Text("Code").tag(MarkdownOptions.FrontMatter.code.rawValue)
                    Text("Hidden").tag(MarkdownOptions.FrontMatter.hidden.rawValue)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}
