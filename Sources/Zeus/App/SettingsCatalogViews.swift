import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZeusCore

/// The sidebar search capsule.
struct SettingsSearchField: View {
    let navigation: SettingsNavigation
    var body: some View {
        GlassSearchField(placeholder: "Search settings", text: Binding(get: { navigation.query }, set: { navigation.query = $0 }),
                         focusToken: navigation.focusSearch, onSubmit: { navigation.openFirstHit() })
    }
}

/// Every option matching the sidebar query, grouped by section. Click a row to open its page.
struct SettingsSearchResults: View {
    let navigation: SettingsNavigation

    var body: some View {
        let hits = navigation.hits
        VStack(alignment: .leading, spacing: Glass.gap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Search").font(Glass.largeTitle).foregroundStyle(Glass.text)
                Text(hits.isEmpty ? "Nothing matches \u{201C}\(navigation.query)\u{201D}." : "\(hits.count) settings match \u{201C}\(navigation.query)\u{201D}. Return opens the first.")
                    .font(Glass.body).foregroundStyle(Glass.secondary)
            }
            .padding(.bottom, 6)
            ForEach(SettingsNavigation.Section.shown.filter { section in hits.contains { $0.section == section } }) { section in
                GlassCard(title: section.title) {
                    let rows = hits.filter { $0.section == section }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, option in
                        if index > 0 { GlassDivider() }
                        Button { navigation.open(section) } label: {
                            HStack(spacing: 12) {
                                GlassIcon(symbol: section.icon.0, tint: section.icon.1, size: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(option.title).font(Glass.body).foregroundStyle(Glass.text)
                                    }
                                    Text("\(option.group) · \(option.note)").font(Glass.caption).foregroundStyle(Glass.secondary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Glass.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(GlassHoverRowStyle())
                    }
                }
            }
        }
    }
}

/// Row hover and press feedback for list rows that are buttons.
struct GlassHoverRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1).scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(Glass.quick, value: configuration.isPressed)
    }
}

/// "Reset section" in the page header; asks for a second press.
struct SectionResetButton: View {
    let navigation: SettingsNavigation
    let section: SettingsNavigation.Section

    var body: some View {
        if SettingsStore.shared.resettable(section) {
            let confirming = navigation.confirmReset == section
            Button {
                if confirming {
                    SettingsStore.shared.reset(section)
                    navigation.confirmReset = nil
                } else {
                    withAnimation(Glass.quick) { navigation.confirmReset = section }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        if navigation.confirmReset == section { withAnimation(Glass.quick) { navigation.confirmReset = nil } }
                    }
                }
            } label: {
                Label(confirming ? "Press again to reset" : "Reset section", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(GlassButtonStyle(kind: confirming ? .danger : .quiet, compact: true))
            .help("Puts every option on this page back to its default.")
        }
    }
}

/// The catalog rows for a section that are not hand-built on its page, as glass cards by group.
struct SettingsOptionCards: View {
    let section: SettingsNavigation.Section

    var body: some View {
        let options = SettingsCatalog.options(in: section).filter { $0.state != .custom }
        let groups = options.reduce(into: [String]()) { list, option in if !list.contains(option.group) { list.append(option.group) } }
        ForEach(groups, id: \.self) { group in
            GlassCard(title: group) {
                let rows = options.filter { $0.group == group }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, option in
                    if index > 0 { GlassDivider() }
                    SettingOptionRow(option: option)
                }
            }
        }
    }
}

struct SettingOptionRow: View {
    let option: SettingOption
    private var store: SettingsStore { .shared }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(option.title).font(Glass.body).foregroundStyle(Glass.text)
                }
                Text(option.note).font(Glass.caption).foregroundStyle(Glass.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var control: some View {
        switch option.kind {
        case .toggle:
            if option.id == "general.launchAtLogin" {
                GlassToggle(isOn: Binding(get: { store.bool(option.id) },
                                          set: { store.set(option.id, $0 ? "true" : "false") }), label: option.title)
            } else {
                GlassToggle(isOn: store.boolBinding(option.id), label: option.title)
            }
        case .choice:
            HStack(spacing: 6) {
                let pairs = option.choices.map { ($0, $0) }
                if option.choices.count <= 3, option.choices.joined().count <= 26 {
                    GlassSegmented(options: pairs, selection: store.stringBinding(option.id))
                } else {
                    GlassMenu(options: pairs, selection: store.stringBinding(option.id))
                }
                if option.id.hasPrefix("sound."), option.id.hasSuffix("Style") {
                    Button { SoundStyles.preview(option: option.id) } label: { Image(systemName: "play.fill") }
                        .buttonStyle(GlassButtonStyle(kind: .secondary, compact: true))
                        .accessibilityLabel("Preview \(option.title)")
                }
            }
        case .slider:
            if let range = option.range {
                GlassStepper(value: Binding(get: { Int(store.double(option.id)) },
                                            set: { store.set(option.id, String($0)) }),
                             range: Int(range.min)...Int(range.max), step: Int(range.step)) { "\($0) %" }
            }
        case .text:
            GlassField(placeholder: option.defaultValue.isEmpty ? "Comma separated" : option.defaultValue,
                       text: store.stringBinding(option.id), width: 230)
        case .action:
            let action = store.actions[option.id]
            Button(Self.actionTitle(option.id)) { action?() }
                .buttonStyle(GlassButtonStyle(kind: .secondary, compact: true))
                .disabled(action == nil)
                .opacity(action == nil ? 0.5 : 1)
        case .status:
            let status = SettingStatus.value(option.id)
            GlassStatus(ok: status.0, text: status.1)
        }
    }

    static func actionTitle(_ id: String) -> String {
        switch id {
        case "about.checkNow": "Check now"
        case "voice.resetWords": "Reset words"
        case "dictation.copyLast": "Copy"
        case "dictation.licenses": "View"
        case "privacy.openAccessibility": "Open"
        case "diag.restart", "iphone.restart": "Restart"
        default: "Run"
        }
    }
}

/// A live preview of the halo on Appearance: style, arm width, thickness and the cue lights, drawn as you change them.
struct AppearancePreview: View {
    let topBar: TopBarModel?
    private var store: SettingsStore { .shared }

    var body: some View {
        GlassCard(title: "Live preview") {
            stage(phase: 0.35)
            HStack(spacing: 6) {
                chip(topBar?.haloStyle.title ?? "Classic glow")
                chip(store.string("halo.armWidth") + " arms")
                chip("\(Int(store.double("halo.thickness"))) % light")
                chip(HaloEntrance.resolve(store.string("halo.entrance")).title)
                Spacer()
                Text("Changes apply instantly").font(Glass.caption).foregroundStyle(Glass.tertiary)
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(Glass.font(11, .semibold)).foregroundStyle(Glass.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Glass.fillRaised))
    }

    /// The same drawing the notch uses (HaloRenderer), on a dark stage.
    private func stage(phase: Double) -> some View {
        let style = topBar?.haloStyle ?? .classic
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1E2233), Color(hex: 0x0E1018)], startPoint: .top, endPoint: .bottom))
            HaloOutline(style: style, arm: store.string("halo.armWidth"), thickness: max(100, store.double("halo.thickness")) / 100,
                        drawn: 1, animated: !TopBarStyle.isSnapshot)
                .frame(width: 260, height: 81)
        }
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Glass.hairline, lineWidth: 1))
        .accessibilityLabel("Halo preview")
    }
}

/// Export and import every setting as JSON, on General.
struct SettingsFileCard: View {
    let navigation: SettingsNavigation

    var body: some View {
        GlassCard(title: "Your settings") {
            GlassRow(title: "Export or import settings", note: navigation.fileNote.isEmpty
                     ? "A JSON file of every option, to move ZEUS to another Mac. Keys and secrets are never included."
                     : navigation.fileNote, icon: ("square.and.arrow.up.on.square", Theme.sky)) {
                HStack(spacing: 6) {
                    Button("Export…") { exportFile() }.buttonStyle(GlassButtonStyle(kind: .secondary, compact: true))
                    Button("Import…") { importFile() }.buttonStyle(GlassButtonStyle(kind: .secondary, compact: true))
                }
            }
        }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ZEUS Settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsStore.shared.exportJSON().write(to: url, options: .atomic)
            navigation.fileNote = "Saved \(url.lastPathComponent)."
        } catch {
            navigation.fileNote = "Could not save: \(error.localizedDescription)"
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try SettingsStore.shared.importJSON(Data(contentsOf: url))
            navigation.fileNote = "Imported \(count) values. Top Bar and Dictation values apply after a relaunch."
        } catch {
            navigation.fileNote = "That file is not a ZEUS settings export."
        }
    }
}
