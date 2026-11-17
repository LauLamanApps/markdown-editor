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

        let baseDir = url.deletingLastPathComponent()
        var renderer = MarkdownRenderer(imageResolver: { ImageInliner.dataURI(for: $0, relativeTo: baseDir) })
        let html = HTMLDocument.wrap(body: renderer.render(markdown), title: url.lastPathComponent)
        log.info("rendered \(url.lastPathComponent, privacy: .public): \(html.utf8.count) bytes")

        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 1100)) { reply in
            reply.stringEncoding = .utf8
            reply.title = url.lastPathComponent
            return Data(html.utf8)
        }
    }
}
