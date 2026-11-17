import Foundation
import UniformTypeIdentifiers

/// Previews can't follow file references next to the document (Quick Look's
/// sandbox, the editor's in-memory page), so local images are embedded as
/// data: URIs. Results are cached per file and modification date, because the
/// editor re-renders on every keystroke.
enum ImageInliner {
    static let maxBytes = 20 * 1024 * 1024

    private static var cache: [String: (modified: Date, uri: String)] = [:]
    private static let lock = NSLock()

    /// The local file an image `src` refers to, or nil for remote and data: sources.
    static func localFile(for src: String, relativeTo base: URL) -> URL? {
        let lower = src.lowercased()
        if lower.hasPrefix("http:") || lower.hasPrefix("https:") || lower.hasPrefix("data:") { return nil }
        if lower.hasPrefix("file://") { return URL(string: src) }
        let path = (src.removingPercentEncoding ?? src).components(separatedBy: CharacterSet(charactersIn: "?#"))[0]
        return path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : base.appendingPathComponent(path).standardizedFileURL
    }

    static func dataURI(for src: String, relativeTo base: URL) -> String? {
        guard let fileURL = localFile(for: src, relativeTo: base) else { return nil }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int, size <= maxBytes else { return nil }
        let modified = attrs[.modificationDate] as? Date ?? .distantPast

        lock.lock()
        if let hit = cache[fileURL.path], hit.modified == modified { lock.unlock(); return hit.uri }
        lock.unlock()

        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let uri = "data:\(mime);base64,\(data.base64EncodedString())"

        lock.lock()
        cache[fileURL.path] = (modified, uri)
        lock.unlock()
        return uri
    }
}
