import Foundation

/// Preview stylesheets shipped in `Resources/Web/themes`.
enum PreviewTheme: String, CaseIterable {
    case github, clean, paper, solarized

    static let key = "PreviewTheme"

    var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .clean: return "Clean"
        case .paper: return "Paper"
        case .solarized: return "Solarized"
        }
    }
}

/// Locates the web assets (stylesheets, scripts, vendored libraries).
enum WebAssets {
    /// `Contents/Resources/Web` in the app and the extension; `Resources/Web` in a
    /// checkout when running md2html.
    static let root: URL = {
        if let bundled = Bundle.main.url(forResource: "Web", withExtension: nil) { return bundled }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        for base in [URL(fileURLWithPath: FileManager.default.currentDirectoryPath), exe.deletingLastPathComponent().deletingLastPathComponent()] {
            let candidate = base.appendingPathComponent("Resources/Web")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return URL(fileURLWithPath: "Resources/Web")
    }()

    private static var cache: [PreviewTheme: String] = [:]
    private static let lock = NSLock()

    /// Base stylesheet plus the theme's variables.
    static func stylesheet(_ theme: PreviewTheme) -> String {
        lock.lock(); defer { lock.unlock() }
        if let css = cache[theme] { return css }
        let base = (try? String(contentsOf: root.appendingPathComponent("base.css"), encoding: .utf8)) ?? ""
        let vars = (try? String(contentsOf: root.appendingPathComponent("themes/\(theme.rawValue).css"), encoding: .utf8)) ?? ""
        let css = vars + "\n" + base
        cache[theme] = css
        return css
    }
}

/// Wraps rendered Markdown in a standalone HTML page.
enum HTMLDocument {
    static func wrap(body: String, title: String, theme: PreviewTheme = .github, head: String = "") -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(escape(title))</title>
        <style>
        \(WebAssets.stylesheet(theme))
        </style>
        \(head)
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }
}
