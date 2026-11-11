import AppKit
import SwiftUI
import ZeusCore

/// The links the About page offers. A link that is nil is not drawn.
enum AboutLinks {
    /// Set this to the owner's LinkedIn profile URL; the button stays hidden while it is nil.
    static let linkedIn: URL? = nil
    static let github = URL(string: "https://github.com/mysticalsin/Zeus-native")
}

/// What the About page prints about this build, read from the app's Info.plist.
enum AboutInfo {
    static func versionLine(short: String?, build: String?) -> String {
        switch (short, build) {
        case let (short?, build?) where !short.isEmpty && !build.isEmpty: "Version \(short) (\(build))"
        case let (short?, _) where !short.isEmpty: "Version \(short)"
        default: "Development build"
        }
    }

    static var currentVersionLine: String {
        let info = Bundle.main.infoDictionary
        return versionLine(short: info?["CFBundleShortVersionString"] as? String, build: info?["CFBundleVersion"] as? String)
    }

    static let builder = "Tony Walteur"
    static let copyright = "\u{00A9} 2026 Tony Walteur"
    static let privacySummary = "Your audio and saved voices stay on this Mac unless you pick a cloud engine, which sends audio to that provider. API keys are kept in the macOS Keychain. Zeus has no telemetry."

    /// The third-party notices shipped inside the app bundle, if this build carries them.
    static func notices() -> String? {
        guard let url = Bundle.main.url(forResource: "NOTICES", withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// Settings, About: who built Zeus, which version this is, and where to find the rest.
struct AboutPage: View {
    let navigation: GSNavigation
    @State private var checked = false
    @State private var showNotices = false

    var body: some View {
        GSPageHeading(section: .about, subtitle: "")
            .padding(.bottom, -GS.cardGap)
        VStack(spacing: 8) {
            AboutIcon()
                .padding(.bottom, 8)
            Text("Zeus").font(GS.wordmark).tracking(-0.8).foregroundStyle(GS.text)
                .accessibilityAddTraits(.isHeader)
            Text(AboutInfo.currentVersionLine).font(OB.font(14, .medium)).monospacedDigit().foregroundStyle(GS.secondary)
            Text("Built by \(AboutInfo.builder)").font(GS.rowText).foregroundStyle(GS.secondary)
            HStack(spacing: 10) {
                if let url = AboutLinks.linkedIn { linkButton("LinkedIn", symbol: "person.crop.square", url: url) }
                if let url = AboutLinks.github { linkButton("GitHub", symbol: "chevron.left.forwardslash.chevron.right", url: url) }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        GSCard {
            GSRow(symbol: "arrow.triangle.2.circlepath", title: "Check for Updates",
                  text: checked ? "Checked. An available update appears at the top of this page." : nil) {
                Button("Check now") {
                    UpdateCoordinator.shared.refreshBadge()
                    checked = true
                }.buttonStyle(GSButtonStyle())
            }
            GSDivider()
            GSRow(symbol: "doc.text", title: "Acknowledgements", text: "Open-source projects and fonts that ship with Zeus.") {
                Button("Show") { showNotices = true }.buttonStyle(GSButtonStyle())
            }
            GSDivider()
            GSRow(symbol: "lock.shield", title: "Privacy", text: AboutInfo.privacySummary) {
                Button("Privacy settings") { navigation.section = .privacy }.buttonStyle(GSButtonStyle())
            }
        }
        Text(AboutInfo.copyright).font(OB.font(12.5)).foregroundStyle(GS.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        .sheet(isPresented: $showNotices) { AboutNoticesSheet() }
    }

    private func linkButton(_ title: String, symbol: String, url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(GSButtonStyle())
        .accessibilityLabel("Open \(title) in your browser")
    }
}

/// The app icon with one slow, soft sweep of light when the page appears (none with Reduce Motion).
private struct AboutIcon: View {
    @State private var sweep: CGFloat = -0.7

    var body: some View {
        let icon = Image(nsImage: NSApp.applicationIconImage)
            .resizable().interpolation(.high)
            .frame(width: 96, height: 96)
        icon
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, .white.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.55)
                        .offset(x: sweep * proxy.size.width)
                }
                .mask { icon }
                .allowsHitTesting(false)
            }
            .accessibilityHidden(true)
            .onAppear {
                guard !Motion.reduced else { return }
                withAnimation(.easeInOut(duration: 1.8).delay(0.35)) { sweep = 1.0 }
            }
    }
}

/// NOTICES.txt in a plain scrollable sheet.
private struct AboutNoticesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = AboutInfo.notices()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Acknowledgements").font(GS.cardTitle).foregroundStyle(GS.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(GSButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(GS.cardInset)
            GSDivider()
            ScrollView {
                Text(text ?? "The acknowledgements file is not included in this build.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(GS.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(GS.cardInset)
            }
        }
        .frame(width: 640, height: 520)
        .background(GS.panel)
    }
}
