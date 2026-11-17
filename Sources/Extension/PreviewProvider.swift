import Cocoa
import QuickLookUI
import UniformTypeIdentifiers
import os

private let log = Logger(subsystem: "io.github.laulaman.MarkdownPreview", category: "preview")

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

/// Quick Look's web view can't follow file references next to the document,
/// so local images are embedded as data: URIs.
enum ImageInliner {
    static let maxBytes = 20 * 1024 * 1024

    static func dataURI(for src: String, relativeTo base: URL) -> String? {
        let lower = src.lowercased()
        if lower.hasPrefix("http:") || lower.hasPrefix("https:") || lower.hasPrefix("data:") { return nil }

        let fileURL: URL
        if lower.hasPrefix("file://") {
            guard let u = URL(string: src) else { return nil }
            fileURL = u
        } else {
            let path = (src.removingPercentEncoding ?? src).components(separatedBy: CharacterSet(charactersIn: "?#"))[0]
            fileURL = path.hasPrefix("/")
                ? URL(fileURLWithPath: path)
                : base.appendingPathComponent(path).standardizedFileURL
        }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int, size <= maxBytes,
              let data = try? Data(contentsOf: fileURL) else { return nil }

        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}
