# Markdown Preview for Quick Look

Select a Markdown file in Finder, press **Space**, and see it rendered — headings, tables, code blocks, task lists and images — instead of raw text.

- GitHub-flavoured Markdown: tables, task lists, ~~strikethrough~~, autolinks, fenced code, alerts (`> [!NOTE]`), YAML front matter
- Follows light / dark mode
- Shows images next to the file (`![](img/diagram.png)`) as well as remote ones
- Zero dependencies, tiny, builds with the Command Line Tools — no Xcode needed
- macOS 12 Monterey or later

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/LauLaman/markdown-preview/main/install.sh | bash
```

This downloads the source, builds it on your Mac and installs `MarkdownPreview.app` into `/Applications` (or `~/Applications` if `/Applications` isn't writable). Because it is built locally, Gatekeeper doesn't block it. The only requirement is the Xcode Command Line Tools; the script offers to install them if they're missing.

### From source

```bash
git clone https://github.com/LauLaman/markdown-preview.git
cd markdown-preview
make install
```

### Prebuilt download

Every [release](https://github.com/LauLaman/markdown-preview/releases) has a universal (Apple silicon + Intel) `MarkdownPreview-x.y.z.zip`. The build isn't notarized, so after unzipping, clear the quarantine flag before opening it:

```bash
xattr -dr com.apple.quarantine MarkdownPreview.app
mv MarkdownPreview.app /Applications/ && open /Applications/MarkdownPreview.app
```

## Usage

Select any `.md` / `.markdown` file in Finder and press Space.

Still seeing plain text?

1. Open **System Settings → General → Login Items & Extensions → Quick Look** and make sure **Markdown Preview** is enabled.
2. Reset Quick Look: `qlmanage -r && qlmanage -r cache`, then relaunch Finder (⌥-right-click the Finder icon → Relaunch).
3. Another app might have claimed `.md` previews (e.g. QLMarkdown). Turn its extension off in the same settings pane.

## Uninstall

```bash
make uninstall          # from a clone
# or
rm -rf /Applications/MarkdownPreview.app && qlmanage -r
```

## Development

```bash
make app        # build build/MarkdownPreview.app for this Mac's architecture
make install    # build, copy to /Applications and register the extension
make test       # snapshot tests for the Markdown renderer
make release    # zip for distribution (pass ARCHS="arm64 x86_64" for universal; needs full Xcode)
```

`build/md2html file.md > out.html` renders a file the same way the extension does, which is handy for checking output in a browser.

After changing a snapshot on purpose, regenerate it with `UPDATE=1 make test`.

Extension logs: `log stream --predicate 'subsystem == "io.github.laulaman.MarkdownPreview"' --info`

### Layout

```
Sources/Shared/     Markdown → HTML renderer and page stylesheet
Sources/Extension/  Quick Look preview provider (QLPreviewProvider)
Sources/App/        Minimal host app that carries the extension
Sources/CLI/        md2html, used by the tests
Resources/          Info.plists and entitlements
Tests/cases/        Snapshot tests (.md input → expected .html)
```

### How it works

The extension is a data-based Quick Look preview: it reads the file, converts it to HTML with a small built-in renderer and returns the HTML to Quick Look, which shows it in its own web view. Quick Look doesn't run JavaScript in these previews, so all rendering happens in Swift. Local images are inlined as `data:` URIs, because the preview can't follow file references next to the document.

### Releasing

Push a tag like `v1.1.0`. The release workflow runs the tests, builds a universal app and attaches the zip to a GitHub release.

## License

MIT
