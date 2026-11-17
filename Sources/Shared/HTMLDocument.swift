import Foundation

/// Wraps rendered Markdown in a standalone HTML page with GitHub-like styling.
enum HTMLDocument {
    static func wrap(body: String, title: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(escape(title))</title>
        <style>\(css)</style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    static let css = """
    :root {
      --fg: #1f2328; --muted: #59636e; --bg: #ffffff; --border: #d1d9e0;
      --code-bg: #f6f8fa; --link: #0969da; --quote: #59636e; --row-alt: #f6f8fa;
      --note: #0969da; --tip: #1a7f37; --important: #8250df; --warning: #9a6700; --caution: #d1242f;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --fg: #e6edf3; --muted: #9198a1; --bg: #0d1117; --border: #3d444d;
        --code-bg: #151b23; --link: #4493f8; --quote: #9198a1; --row-alt: #151b23;
        --note: #4493f8; --tip: #3fb950; --important: #ab7df8; --warning: #d29922; --caution: #f85149;
      }
    }
    html { background: var(--bg); }
    body {
      margin: 0; padding: 32px 40px; color: var(--fg); background: var(--bg);
      font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue", Arial, sans-serif;
      -webkit-font-smoothing: antialiased; word-wrap: break-word;
    }
    .markdown-body { max-width: 900px; margin: 0 auto; }
    .markdown-body > *:first-child { margin-top: 0 !important; }
    h1, h2, h3, h4, h5, h6 { margin: 24px 0 16px; font-weight: 600; line-height: 1.25; }
    h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
    h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
    h3 { font-size: 1.25em; } h4 { font-size: 1em; } h5 { font-size: .875em; }
    h6 { font-size: .85em; color: var(--muted); }
    p, blockquote, ul, ol, dl, table, pre, details, .alert { margin: 0 0 16px; }
    a { color: var(--link); text-decoration: none; } a:hover { text-decoration: underline; }
    hr { height: 4px; padding: 0; margin: 24px 0; background: var(--border); border: 0; border-radius: 2px; }
    blockquote { padding: 0 1em; color: var(--quote); border-left: .25em solid var(--border); }
    blockquote > :last-child, .alert > :last-child { margin-bottom: 0; }
    ul, ol { padding-left: 2em; } li + li { margin-top: .25em; } li > p { margin-top: 16px; }
    ul ul, ul ol, ol ol, ol ul { margin-bottom: 0; }
    .task-list-item { list-style: none; } .task-list-item input { margin: 0 .3em .2em -1.4em; vertical-align: middle; }
    code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 85%; }
    code { padding: .2em .4em; background: var(--code-bg); border-radius: 6px; }
    pre { padding: 16px; overflow: auto; line-height: 1.45; background: var(--code-bg); border-radius: 6px; }
    pre code { padding: 0; background: transparent; font-size: 100%; white-space: pre; }
    pre.front-matter { border: 1px dashed var(--border); color: var(--muted); }
    table { border-spacing: 0; border-collapse: collapse; display: block; width: max-content; max-width: 100%; overflow: auto; }
    th, td { padding: 6px 13px; border: 1px solid var(--border); }
    th { font-weight: 600; } tr:nth-child(2n) { background: var(--row-alt); }
    img { max-width: 100%; box-sizing: border-box; }
    kbd { padding: 3px 5px; font: 11px ui-monospace, monospace; border: 1px solid var(--border); border-radius: 6px; background: var(--code-bg); }
    .alert { padding: 8px 16px; border-left: .25em solid var(--alert); }
    .alert-title { font-weight: 600; color: var(--alert); margin-bottom: 4px; }
    .alert-note { --alert: var(--note); } .alert-tip { --alert: var(--tip); }
    .alert-important { --alert: var(--important); } .alert-warning { --alert: var(--warning); }
    .alert-caution { --alert: var(--caution); }
    """
}
