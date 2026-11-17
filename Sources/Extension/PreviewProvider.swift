import Cocoa
import QuickLookUI
import UniformTypeIdentifiers
import os

private let log = Logger(subsystem: "nl.LauLamanApps.MarkdownPreview", category: "preview")

/// Data-based Quick Look preview: renders the Markdown file to HTML and hands
/// it to Quick Look, which displays it in its own web view.
class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let data = try Data(contentsOf: url)
        let markdown = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""

        let prefs = AppPreferences.load()
        let baseDir = url.deletingLastPathComponent()
        var renderer = MarkdownRenderer(options: MarkdownOptions(prefs),
                                        imageResolver: { ImageInliner.dataURI(for: $0, relativeTo: baseDir) })
        let theme = (prefs[PreviewTheme.key] as? String).flatMap(PreviewTheme.init) ?? .github
        let html = HTMLDocument.wrap(body: renderer.render(markdown), title: url.lastPathComponent, theme: theme)
        log.info("rendered \(url.lastPathComponent, privacy: .public): \(html.utf8.count) bytes")

        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 1100)) { reply in
            reply.stringEncoding = .utf8
            reply.title = url.lastPathComponent
            return Data(html.utf8)
        }
    }
}

/// The editor app's settings. The extension is sandboxed and has its own
/// defaults domain, so it reads the app's preferences file directly (allowed
/// by its read-only file exception).
enum AppPreferences {
    static func load() -> [String: Any] {
        guard let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir else { return [:] }
        let appID = (Bundle.main.bundleIdentifier ?? "").replacingOccurrences(of: ".QuickLook", with: "")
        let file = URL(fileURLWithPath: String(cString: home))
            .appendingPathComponent("Library/Preferences/\(appID).plist")
        return NSDictionary(contentsOf: file) as? [String: Any] ?? [:]
    }
}
