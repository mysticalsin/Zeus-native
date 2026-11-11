import AppKit
import Observation
import SwiftUI
import ZeusCore

/// Glance's Settings sections, in its sidebar order and groups.
enum GSSection: String, CaseIterable, Identifiable, Sendable {
    case general, appearance, sounds, notifications, shortcuts, insomnia
    case integrations, murmure, polyglot, dictation, voice, engine, iPhone
    case license, permissions, privacy, diagnostics
    case features, beamer

    var id: String { rawValue }

    enum Group: String, CaseIterable { case settings = "Settings", tools = "Your tools", app = "Zeus" }

    var group: Group {
        switch self {
        case .general, .appearance, .sounds, .notifications, .shortcuts, .insomnia: .settings
        case .integrations, .murmure, .polyglot, .dictation, .voice, .engine, .iPhone, .features, .beamer: .tools
        case .license, .permissions, .privacy, .diagnostics: .app
        }
    }

    /// Zeus has no iPhone companion to pair yet, so that page would be a single "Not available" row:
    /// the sidebar hides it until pairing exists (flip `iPhonePairingAvailable` then).
    static let iPhonePairingAvailable = false

    var isShown: Bool { self == .iPhone ? Self.iPhonePairingAvailable : true }

    static var shown: [GSSection] { allCases.filter(\.isShown) }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .sounds: "Sounds"
        case .notifications: "Notifications"
        case .shortcuts: "Shortcuts"
        case .insomnia: "Insomnia"
        case .integrations: "Integrations"
        case .murmure: "Murmure"
        case .polyglot: "Polyglot"
        case .dictation: "Dictation"
        case .voice: "Voice"
        case .engine: "Engine"
        case .iPhone: "iPhone"
        case .features: "Features"
        case .beamer: "Beamer"
        case .license: "License"
        case .permissions: "Permissions"
        case .privacy: "Privacy"
        case .diagnostics: "Diagnostics"
        }
    }

    /// Resolves a debug `open-settings` section by raw id, title, or legacy alias (R24).
    static func matching(_ name: String) -> GSSection? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let direct = allCases.first(where: { $0.rawValue.lowercased() == key || $0.title.lowercased() == key }) {
            return direct
        }
        guard let id = GlanceSettingsSnapshotMapping.resolveSectionID(name) else { return nil }
        return allCases.first { $0.rawValue.lowercased() == id.lowercased() }
    }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .appearance: "circle.lefthalf.filled"
        case .sounds: "speaker.wave.2"
        case .notifications: "bell"
        case .shortcuts: "keyboard"
        case .insomnia: "moon.zzz"
        case .integrations: "link"
        case .murmure: "water.waves"
        case .polyglot: "globe"
        case .dictation: "mic"
        case .voice: "waveform"
        case .engine: "cpu"
        case .iPhone: "iphone"
        case .features: "switch.2"
        case .beamer: "rectangle.connected.to.line.below"
        case .license: "key"
        case .permissions: "checkmark.shield"
        case .privacy: "lock.shield"
        case .diagnostics: "waveform.path.ecg.rectangle"
        }
    }
}

@MainActor
@Observable
final class GSNavigation {
    var section: GSSection = .general
    var meetingOpen = false
    var licenseKey = ""
    var licenseMessage: String?
}

/// The Settings window: 1080 x 780, the sidebar and the page panel.
@MainActor
final class GlanceSettingsWindowController: NSObject, NSWindowDelegate {
    let navigation = GSNavigation()
    private var window: NSWindow?
    private let context: GSContext

    init(context: GSContext) {
        self.context = context
    }

    var isKey: Bool { window?.isKeyWindow == true }
    /// For `zeus debug screenshot --window settings`.
    var debugWindow: NSWindow? { window }

    func show(_ section: GSSection? = nil) {
        if let section { navigation.section = section }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: GS.size),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.title = "Zeus Settings"
            window.delegate = self
            let hosting = NSHostingView(rootView: GlanceSettingsRoot(navigation: navigation, context: context))
            hosting.sizingOptions = []
            window.contentView = hosting
            window.setFrame(NSRect(origin: .zero, size: GS.size), display: false)
            window.center()
            self.window = window
        }
        context.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func step(_ delta: Int) {
        let list = GSSection.shown
        let index = list.firstIndex(of: navigation.section) ?? 0
        navigation.section = list[min(max(index + delta, 0), list.count - 1)]
    }
}

struct GlanceSettingsRoot: View {
    let navigation: GSNavigation
    let context: GSContext
    var body: some View {
        ZStack(alignment: .topLeading) {
            GS.window
            GSSidebar(navigation: navigation)
            GSPanelHost(navigation: navigation, context: context)
                .frame(width: GS.panelFrame.width, height: GS.panelFrame.height)
                .offset(x: GS.panelFrame.minX, y: GS.panelFrame.minY)
        }
        .frame(width: GS.size.width, height: GS.size.height)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

/// Logo tile, wordmark, three groups of items (28 pt apart), version at the foot.
struct GSSidebar: View {
    let navigation: GSNavigation

    var body: some View {
        ZStack(alignment: .topLeading) {
            MascotTile(pose: .idle, side: 48, animated: false).offset(x: 26, y: 48)
            Text("Zeus").font(GS.wordmark).tracking(-1.6).foregroundStyle(GS.text).offset(x: 90, y: 51)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(GSSection.Group.allCases, id: \.self) { group in
                    Text(group.rawValue).font(GS.sidebarHead).foregroundStyle(GS.secondary)
                        .frame(height: 20, alignment: .leading)
                        .padding(.leading, 14)
                        .padding(.top, group == .settings ? 0 : 8.5)
                        .padding(.bottom, 5)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(GSSection.shown.filter { $0.group == group }) { section in
                        item(section)
                    }
                }
            }
            .frame(width: 194)
            .offset(x: 12, y: 114)
            Text("Zeus \(Self.version)").font(OB.font(13)).foregroundStyle(GS.secondary).offset(x: 26, y: 751)
        }
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1" }

    private func item(_ section: GSSection) -> some View {
        let selected = navigation.section == section
        return Button { navigation.section = section } label: {
            HStack(spacing: 0) {
                Image(systemName: section.symbol).font(.system(size: 15, weight: .regular))
                    .frame(width: 29, alignment: .leading)
                Text(section.title).font(GS.sidebarItem)
                Spacer()
            }
            .foregroundStyle(selected ? GS.selectedText : GS.text)
            .padding(.leading, 14)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? GS.selectedFill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 2)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The rounded panel: page title, subtitle, header glyph and the page's cards, scrolling.
struct GSPanelHost: View {
    let navigation: GSNavigation
    let context: GSContext

    var body: some View {
        let page = GSPageView(section: navigation.section, navigation: navigation, context: context)
            .padding(.leading, GS.pagePadding)
            .padding(.trailing, 28)
            .padding(.top, 25)
            .padding(.bottom, 32)
            .id(navigation.section)
        ZStack {
            RoundedRectangle(cornerRadius: GS.panelRadius, style: .continuous).fill(GS.panel)
            // QA7 round 11 (report-11.md): named surfaces that go through this exact view
            // (`murmur-settings`, every live `settings-<name>` in `SnapshotRenderer.swift`) rendered
            // a blank content pane under `ImageRenderer`'s one-shot `--snapshots` pass -- round 10
            // already found and documented this (`ImageRenderer` never lays out a `ScrollView` on a
            // headless render) and worked around it for the *new*, separately-named `settings-full-*`
            // surfaces it added, but never fixed this view itself, so every snapshot that still asks
            // for the real windowed `GlanceSettingsRoot`/`GSPanelHost` (sidebar and all, which
            // `settings-full-*` deliberately omits) was still blank. Fixed at the root instead of
            // adding yet another parallel surface name: skip the `ScrollView` entirely while
            // snapshotting (no live scrolling needed for a single static frame anyway) so
            // `ImageRenderer` lays out the real page content directly.
            // `fixedSize(vertical:)` hands the page its own height: a taller page would otherwise be
            // proposed the panel's height and centre its overflow, so long pages (Murmure, Voice)
            // rendered scrolled to the middle instead of from the top.
            if TopBarStyle.isSnapshot {
                // A flexible frame would grow with the page and the ZStack would then centre it in the panel;
                // a fixed height with top alignment keeps the page's first line at the panel's top edge.
                page.fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .frame(height: GS.panelFrame.height, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: GS.panelRadius, style: .continuous))
            } else {
                ScrollView(.vertical) { page }
                    .scrollIndicators(.automatic)
                    .clipShape(RoundedRectangle(cornerRadius: GS.panelRadius, style: .continuous))
            }
            RoundedRectangle(cornerRadius: GS.panelRadius, style: .continuous).strokeBorder(GS.panelStroke, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

/// Page heading (Jakarta 29.5 title, subtitle, 24 pt glyph at the right) above the page's cards.
struct GSPageHeading: View {
    let section: GSSection
    let subtitle: String
    var body: some View {
        let _ = SnapshotPaneProbe.note(section.rawValue) // snapshot harness only; no-op outside snapshot mode
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 9) {
                Text(section.title).font(GS.pageTitle).tracking(-1.1).foregroundStyle(GS.text)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Image(systemName: section.symbol).font(.system(size: 24, weight: .regular)).foregroundStyle(GS.text)
                .padding(.top, 8).accessibilityHidden(true)
        }
        .padding(.trailing, 3)
        .padding(.bottom, 31)
    }
}

/// `Zeus --settings-only [--settings-section permissions]`: only the Settings window (no notch, no
/// menu bar item), for live parity captures.
@MainActor
enum GSParity {
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard arguments.contains("--settings-only") else { return false }
        NSApp.setActivationPolicy(.accessory)
        let services = OnboardingServices(permissions: PermissionsModel())
        let controller = GlanceSettingsWindowController(context: GSContext(services: services))
        var section: GSSection?
        if let flag = arguments.firstIndex(of: "--settings-section"), flag + 1 < arguments.count {
            section = GSSection(rawValue: arguments[flag + 1])
        }
        controller.show(section)
        keep = controller
        return true
    }

    private static var keep: GlanceSettingsWindowController?
}
