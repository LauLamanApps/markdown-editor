import Cocoa

/// User preferences, stored in standard user defaults. The Quick Look
/// extension reads the preview and Markdown keys from the same plist.
enum AppSettings {
    enum Key {
        static let previewTheme = PreviewTheme.key
        static let previewAppearance = "PreviewAppearance"
        static let editorFont = "EditorFontName"
        static let editorFontSize = "EditorFontSize"
        static let lineSpacing = "EditorLineSpacing"
        static let editorTheme = "EditorTheme"
        static let readableWidth = "EditorReadableWidth"
        static let lineLength = "EditorLineLength"
        static let autoPair = "EditorAutoPair"
        static let continueLists = "EditorContinueLists"
        static let spacesForTab = "EditorSpacesForTab"
        static let tabWidth = "EditorTabWidth"
        static let syncScroll = "SyncScroll"
        static let trailingNewline = "EnsureTrailingNewline"
        static let statusBar = "ShowStatusBar"
        static let layout = "Layout"
    }

    enum Appearance: String, CaseIterable {
        case system, light, dark
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }
    }

    static let defaultFontSize: CGFloat = 14

    static func register() {
        let o = MarkdownOptions()
        UserDefaults.standard.register(defaults: [
            Key.previewTheme: PreviewTheme.github.rawValue,
            Key.previewAppearance: Appearance.system.rawValue,
            Key.editorFont: "",
            Key.editorFontSize: Double(defaultFontSize),
            Key.lineSpacing: 1.3,
            Key.editorTheme: EditorTheme.system.rawValue,
            Key.readableWidth: true,
            Key.lineLength: 90,
            Key.autoPair: true,
            Key.continueLists: true,
            Key.spacesForTab: true,
            Key.tabWidth: 4,
            Key.syncScroll: true,
            Key.trailingNewline: true,
            Key.statusBar: true,
            MarkdownOptions.Key.math: o.math,
            MarkdownOptions.Key.mermaid: o.mermaid,
            MarkdownOptions.Key.footnotes: o.footnotes,
            MarkdownOptions.Key.highlight: o.highlight,
            MarkdownOptions.Key.tableOfContents: o.tableOfContents,
            MarkdownOptions.Key.hardLineBreaks: o.hardLineBreaks,
            MarkdownOptions.Key.smartPunctuation: o.smartPunctuation,
            MarkdownOptions.Key.frontMatter: o.frontMatter.rawValue,
        ])
    }

    private static var d: UserDefaults { .standard }

    static var markdownOptions: MarkdownOptions { MarkdownOptions(d.dictionaryRepresentation()) }
    static var previewTheme: PreviewTheme { PreviewTheme(rawValue: d.string(forKey: Key.previewTheme) ?? "") ?? .github }
    static var previewAppearance: Appearance { Appearance(rawValue: d.string(forKey: Key.previewAppearance) ?? "") ?? .system }
    static var editorTheme: EditorTheme { EditorTheme(rawValue: d.string(forKey: Key.editorTheme) ?? "") ?? .system }
    static var autoPair: Bool { d.bool(forKey: Key.autoPair) }
    static var continueLists: Bool { d.bool(forKey: Key.continueLists) }
    static var spacesForTab: Bool { d.bool(forKey: Key.spacesForTab) }
    static var tabWidth: Int { max(1, d.integer(forKey: Key.tabWidth)) }
    static var syncScroll: Bool { d.bool(forKey: Key.syncScroll) }
    static var trailingNewline: Bool { d.bool(forKey: Key.trailingNewline) }
    static var statusBar: Bool { d.bool(forKey: Key.statusBar) }
    static var readableWidth: Bool { d.bool(forKey: Key.readableWidth) }
    static var lineLength: Int { max(40, d.integer(forKey: Key.lineLength)) }
    static var lineSpacing: CGFloat { CGFloat(d.double(forKey: Key.lineSpacing)) }

    static var fontSize: CGFloat {
        get { CGFloat(d.double(forKey: Key.editorFontSize)) }
        set { d.set(Double(min(max(newValue, 9), 36)), forKey: Key.editorFontSize) }
    }

    static var editorFont: NSFont {
        let name = d.string(forKey: Key.editorFont) ?? ""
        return EditorFonts.font(named: name, size: fontSize)
    }
}

/// Fonts offered in AppSettings. An empty name means the system monospaced font.
enum EditorFonts {
    static let choices: [(name: String, label: String)] = [
        ("", "SF Mono (System)"),
        ("Menlo-Regular", "Menlo"),
        ("Monaco", "Monaco"),
        ("CourierNewPSMT", "Courier New"),
        ("system-proportional", "San Francisco"),
        ("system-serif", "New York"),
    ]

    static func font(named name: String, size: CGFloat) -> NSFont {
        switch name {
        case "": return .monospacedSystemFont(ofSize: size, weight: .regular)
        case "system-proportional": return .systemFont(ofSize: size)
        case "system-serif":
            let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)
            return descriptor.flatMap { NSFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
        default: return NSFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }
}

/// Colours for the editor's syntax highlighting.
enum EditorTheme: String, CaseIterable {
    case system, solarizedLight, solarizedDark, paper, midnight

    var displayName: String {
        switch self {
        case .system: return "System"
        case .solarizedLight: return "Solarized Light"
        case .solarizedDark: return "Solarized Dark"
        case .paper: return "Paper"
        case .midnight: return "Midnight"
        }
    }

    struct Palette {
        var background, text, muted, accent, code, link, selection, cursor: NSColor
    }

    private static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    /// Forced appearance for fixed-colour themes, so scroll bars and the find bar match.
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .solarizedLight, .paper: return NSAppearance(named: .aqua)
        case .solarizedDark, .midnight: return NSAppearance(named: .darkAqua)
        }
    }

    var palette: Palette {
        switch self {
        case .system:
            return Palette(background: .textBackgroundColor, text: .textColor, muted: .secondaryLabelColor,
                           accent: .controlAccentColor, code: .systemPink, link: .linkColor,
                           selection: .selectedTextBackgroundColor, cursor: .textColor)
        case .solarizedLight:
            return Palette(background: Self.hex(0xfdf6e3), text: Self.hex(0x586e75), muted: Self.hex(0x93a1a1),
                           accent: Self.hex(0xcb4b16), code: Self.hex(0x2aa198), link: Self.hex(0x268bd2),
                           selection: Self.hex(0xeee8d5), cursor: Self.hex(0x657b83))
        case .solarizedDark:
            return Palette(background: Self.hex(0x002b36), text: Self.hex(0x93a1a1), muted: Self.hex(0x586e75),
                           accent: Self.hex(0xcb4b16), code: Self.hex(0x2aa198), link: Self.hex(0x268bd2),
                           selection: Self.hex(0x073642), cursor: Self.hex(0x93a1a1))
        case .paper:
            return Palette(background: Self.hex(0xfbf8f1), text: Self.hex(0x2f2a24), muted: Self.hex(0x9a8f80),
                           accent: Self.hex(0x9c4221), code: Self.hex(0x5f7a2c), link: Self.hex(0x2c5f8a),
                           selection: Self.hex(0xece3cf), cursor: Self.hex(0x2f2a24))
        case .midnight:
            return Palette(background: Self.hex(0x15171c), text: Self.hex(0xd8dae0), muted: Self.hex(0x6c707a),
                           accent: Self.hex(0x7aa2f7), code: Self.hex(0xa3d68c), link: Self.hex(0x82aaff),
                           selection: Self.hex(0x2a2f3a), cursor: Self.hex(0xd8dae0))
        }
    }
}
