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

        // Quick Look's web view loads neither file references, data: URIs nor
        // the network, so every image is handed over as an attachment (cid:).
        let images = ImageAttachments(baseDirectory: baseDir)
        var renderer = MarkdownRenderer(options: MarkdownOptions(prefs), imageResolver: images.reference(for:))
        let theme = (prefs[PreviewTheme.key] as? String).flatMap(PreviewTheme.init) ?? .github
        var html = HTMLDocument.wrap(body: renderer.render(markdown), title: url.lastPathComponent, theme: theme)
        let attachments = await images.load()
        // Images that couldn't be loaded keep their original address
        for (cid, src) in images.sources where attachments[cid] == nil {
            html = html.replacingOccurrences(of: "cid:\(cid)", with: escapeAttr(src))
        }
        log.info("rendered \(url.lastPathComponent, privacy: .public): \(html.utf8.count) bytes, \(attachments.count)/\(images.sources.count) images")

        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 1100)) { reply in
            reply.stringEncoding = .utf8
            reply.title = url.lastPathComponent
            reply.attachments = attachments
            return Data(html.utf8)
        }
    }
}

/// Collects the images a document uses and loads them as preview attachments:
/// local files from disk, remote images over the network (with a short timeout).
final class ImageAttachments {
    private let baseDirectory: URL
    private(set) var sources: [(cid: String, src: String)] = []

    static let maxRemoteBytes = 10 * 1024 * 1024

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    /// Image resolver for the renderer: hands out a cid: reference per image.
    func reference(for src: String) -> String? {
        guard !src.lowercased().hasPrefix("data:") else { return nil }
        if let existing = sources.first(where: { $0.src == src }) { return "cid:\(existing.cid)" }
        let cid = "image-\(sources.count + 1)"
        sources.append((cid, src))
        return "cid:\(cid)"
    }

    func load() async -> [String: QLPreviewReplyAttachment] {
        await withTaskGroup(of: (String, QLPreviewReplyAttachment?).self) { group in
            for (cid, src) in sources {
                group.addTask { [baseDirectory] in (cid, await Self.attachment(for: src, base: baseDirectory)) }
            }
            var result: [String: QLPreviewReplyAttachment] = [:]
            for await (cid, attachment) in group {
                if let attachment { result[cid] = attachment }
            }
            return result
        }
    }

    private static func attachment(for src: String, base: URL) async -> QLPreviewReplyAttachment? {
        if let file = ImageInliner.localFile(for: src, relativeTo: base) {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                  let size = attrs[.size] as? Int, size <= ImageInliner.maxBytes,
                  let data = try? Data(contentsOf: file) else {
                log.error("image not readable: \(file.path, privacy: .public)")
                return nil
            }
            return QLPreviewReplyAttachment(data: data, contentType: UTType(filenameExtension: file.pathExtension) ?? .image)
        }
        guard let url = URL(string: src), url.scheme == "http" || url.scheme == "https" else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log.error("image not downloadable: \(src, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard (response as? HTTPURLResponse)?.statusCode ?? 0 < 400, data.count <= maxRemoteBytes else { return nil }
        let type = response.mimeType.flatMap { UTType(mimeType: $0) }
            ?? UTType(filenameExtension: url.pathExtension) ?? .image
        return QLPreviewReplyAttachment(data: data, contentType: type)
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
