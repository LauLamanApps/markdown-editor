import Cocoa
import SwiftUI

/// About window: icon, version, project links and credits for the bundled components.
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
        let host = NSHostingController(rootView: AboutView())
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "About Markdown Editor"
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private lazy var licensesWindow: NSWindow = {
        let window = NSWindow(contentViewController: NSHostingController(rootView: LicensesView()))
        window.styleMask = [.titled, .closable, .resizable]
        window.title = "Licenses"
        window.setContentSize(NSSize(width: 520, height: 480))
        window.isReleasedWhenClosed = false
        return window
    }()

    func showLicenses() {
        if !licensesWindow.isVisible { licensesWindow.center() }
        licensesWindow.makeKeyAndOrderFront(nil)
    }
}

private enum Links {
    static let repo = URL(string: "https://github.com/LauLamanApps/markdown-editor")!
    static let issues = URL(string: "https://github.com/LauLamanApps/markdown-editor/issues")!
    static let releases = URL(string: "https://github.com/LauLamanApps/markdown-editor/releases")!
}

private struct Credit: Identifiable {
    let name: String
    let role: String
    let license: String
    let url: URL
    /// Text file in ThirdPartyLicenses, if the component ships its own license
    var file: String?
    var id: String { name }
}

private let credits = [
    Credit(name: "Prism", role: "Code highlighting", license: "MIT", url: URL(string: "https://prismjs.com")!, file: "prism"),
    Credit(name: "KaTeX", role: "Math typesetting", license: "MIT", url: URL(string: "https://katex.org")!, file: "katex"),
    Credit(name: "Mermaid", role: "Diagrams", license: "MIT", url: URL(string: "https://mermaid.js.org")!, file: "mermaid"),
    Credit(name: "Markdown Mark", role: "Icon artwork, by Dustin Curtis", license: "Public domain",
           url: URL(string: "https://github.com/dcurtis/markdown-mark")!),
    Credit(name: "MacDown", role: "Inspiration for the feature set", license: "MIT",
           url: URL(string: "https://github.com/MacDownApp/macdown")!),
]

private struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        return "Version \(short)"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .padding(.bottom, 6)
                Text("Markdown Editor")
                    .font(.system(size: 22, weight: .semibold))
                Text(version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Write Markdown with a live preview, and see it rendered in Finder with Quick Look.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 36)
            .padding(.bottom, 18)

            HStack(spacing: 8) {
                LinkButton(title: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", url: Links.repo)
                LinkButton(title: "Releases", symbol: "shippingbox", url: Links.releases)
                LinkButton(title: "Report an Issue", symbol: "ladybug", url: Links.issues)
            }
            .padding(.bottom, 20)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Built with")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(credits) { credit in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Link(credit.name, destination: credit.url)
                                .font(.callout.weight(.medium))
                            Text(credit.role)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(credit.license)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            HStack {
                Text("© 2026 LauLamanApps · MIT License")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Licenses…") { AboutWindowController.shared.showLicenses() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(width: 380)
        .background(VisualEffect().ignoresSafeArea())
    }
}

private struct LinkButton: View {
    let title: String
    let symbol: String
    let url: URL

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Label(title, systemImage: symbol)
        }
        .controlSize(.regular)
    }
}

/// License texts for the app and the bundled third-party components.
private struct LicensesView: View {
    private var sections: [(title: String, text: String)] {
        var result: [(String, String)] = []
        if let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            result.append(("Markdown Editor", text))
        }
        for credit in credits {
            guard let file = credit.file,
                  let url = Bundle.main.url(forResource: file, withExtension: "txt", subdirectory: "ThirdPartyLicenses"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            result.append((credit.name, text))
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title).font(.headline)
                        Text(section.text)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 420, idealWidth: 520, minHeight: 300, idealHeight: 480)
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
