import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves the bundled web assets (scripts, styles, fonts) to the preview as mdp://app/….
final class WebResourceHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mdp"

    /// Scripts for the live preview: Prism, plus preview.js which loads KaTeX and Mermaid on demand.
    static let previewHead = """
        <script>window.Prism = { manual: true };</script>
        <script src="\(scheme)://app/vendor/prism.js"></script>
        <script src="\(scheme)://app/preview.js"></script>
        """

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let root = WebAssets.root.standardizedFileURL
        let file = root.appendingPathComponent(url.path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mime,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "max-age=86400",
        ])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
