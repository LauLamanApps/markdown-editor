import Foundation

// Renders a Markdown file to HTML on stdout: a full page by default, or just
// the body with --fragment. Used by `make test` and handy for checking output
// without Quick Look.

var args = Array(CommandLine.arguments.dropFirst())
let fragment = args.contains("--fragment")
// Tests: prefix resolved image sources, to show which images went through the resolver
let markImages = args.contains("--mark-images")
args.removeAll { $0 == "--fragment" || $0 == "--mark-images" }

guard args.count == 1 else {
    FileHandle.standardError.write(Data("usage: md2html [--fragment] [--mark-images] <file.md>\n".utf8))
    exit(64)
}
let url = URL(fileURLWithPath: args[0])
guard let data = try? Data(contentsOf: url) else {
    FileHandle.standardError.write(Data("cannot read \(args[0])\n".utf8))
    exit(66)
}
let markdown = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
var renderer = MarkdownRenderer(imageResolver: markImages ? { "resolved:" + $0 } : nil)
let body = renderer.render(markdown)
print(fragment ? body : HTMLDocument.wrap(body: body, title: url.lastPathComponent), terminator: "")
