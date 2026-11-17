import Foundation

// Renders a Markdown file to HTML on stdout: a full page by default, or just
// the body with --fragment. Used by `make test` and handy for checking output
// without Quick Look.

var args = Array(CommandLine.arguments.dropFirst())
let fragment = args.contains("--fragment")
args.removeAll { $0 == "--fragment" }

guard args.count == 1 else {
    FileHandle.standardError.write(Data("usage: md2html [--fragment] <file.md>\n".utf8))
    exit(64)
}
let url = URL(fileURLWithPath: args[0])
guard let data = try? Data(contentsOf: url) else {
    FileHandle.standardError.write(Data("cannot read \(args[0])\n".utf8))
    exit(66)
}
let markdown = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
var renderer = MarkdownRenderer()
let body = renderer.render(markdown)
print(fragment ? body : HTMLDocument.wrap(body: body, title: url.lastPathComponent), terminator: "")
