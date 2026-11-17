import Cocoa
import WebKit

// Loads a Markdown file into the same web view setup the editor uses and
// reports what the preview scripts produced: highlighted tokens, rendered
// math and diagrams. Exits non-zero if something expected didn't render.

let args = CommandLine.arguments
guard args.count == 2, let markdown = try? String(contentsOfFile: args[1], encoding: .utf8) else {
    FileHandle.standardError.write(Data("usage: preview-check <file.md>\n".utf8))
    exit(64)
}

final class Checker: NSObject, WKNavigationDelegate {
    let web: WKWebView
    var attempts = 0

    override init() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(WebResourceHandler(), forURLScheme: WebResourceHandler.scheme)
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1200), configuration: config)
        super.init()
        web.navigationDelegate = self
    }

    func start(_ markdown: String) {
        var renderer = MarkdownRenderer()
        let html = HTMLDocument.wrap(body: renderer.render(markdown), title: "check", head: WebResourceHandler.previewHead)
        web.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { poll() }

    func poll() {
        let js = """
        JSON.stringify({
          codeBlocks: document.querySelectorAll('pre code[class*=language-]').length,
          tokens: document.querySelectorAll('.token').length,
          math: document.querySelectorAll('.math').length,
          mathRendered: document.querySelectorAll('.math.rendered .katex').length,
          diagrams: document.querySelectorAll('pre.mermaid').length,
          diagramsRendered: document.querySelectorAll('pre.mermaid[data-processed=true] svg').length,
          diagramErrors: [...document.querySelectorAll('pre.mermaid[data-processed=error]')].map(e => e.title),
        })
        """
        web.evaluateJavaScript(js) { result, error in
            self.attempts += 1
            guard let json = result as? String,
                  let r = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
                print("error:", error?.localizedDescription ?? "no result"); exit(1)
            }
            let int = { (k: String) in r[k] as? Int ?? 0 }
            let done = int("mathRendered") == int("math") && int("diagramsRendered") + ((r["diagramErrors"] as? [Any])?.count ?? 0) == int("diagrams")
                && (int("codeBlocks") == 0 || int("tokens") > 0)
            if done || self.attempts > 40 {
                print(json)
                let ok = done && (r["diagramErrors"] as? [Any])?.isEmpty != false
                print(ok ? "✓ preview rendered" : "✗ preview incomplete")
                exit(ok ? 0 : 1)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.poll() }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let checker = Checker()
checker.start(markdown)
app.run()
