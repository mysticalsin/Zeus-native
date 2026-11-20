import IOKit
import SwiftUI
import ZeusCore

extension Notification.Name {
    static let zeusGeneralOpenAppearance = Notification.Name("zeusGeneralOpenAppearance")
}

extension GeneralSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(GeneralSettingsSection()) }
}

struct GeneralSettingsSection: View {
    @State private var reset = GeneralResetConfirmation.idle
    @State private var hapticsLoaded = false
    @State private var forceTouch = false

    var body: some View {
        let chrome = GeneralResetConfirmation.chrome(reset)
        let appearance = WindowAppearance.resolve(store.string(WindowAppearance.key))
        let blur = GeneralBlurStrength.parse(store.string(GeneralBlurStrength.key))
        let preview = GeneralWindowPreview.make(
            appearance: appearance,
            systemIsLight: colorScheme == .light,
            blur: blur,
            reduceMotion: Motion.reduced,
            reduceTransparency: reduceTransparency
        )
        let haptic = GeneralHaptics.readout(
            loaded: hapticsLoaded,
            storedOn: store.bool(GeneralHaptics.key),
            forceTouch: forceTouch,
            failure: nil
        )
        VStack(alignment: .leading, spacing: CGFloat(GlassSettingsMetrics.cardSpacing)) {
            if NSScreen.screens.isEmpty {
                GSEmptyState(symbol: "display", title: "No display is connected.", text: "The notch appears when a display is connected.")
                    .accessibilityLabel("No display is connected.")
            }
            card("Window") {
                row("Window appearance", "System, Light, or Dark. The welcome guide uses the same choice.", "Window appearance") {
                    GSPopup(
                        selection: Binding(
                            get: { WindowAppearance.resolve(store.string(WindowAppearance.key)).rawValue },
                            set: { store.set(WindowAppearance.key, $0) }
                        ),
                        options: GeneralSettingsSectionModel.appearanceChoices,
                        label: "Window appearance"
                    )
                }
                previewTile(preview)
                divider
                row("Background blur", "0 is no blur and 100 is the strongest.", "Background blur strength") {
                    Slider(
                        value: Binding(
                            get: { GeneralBlurStrength.parse(store.string(GeneralBlurStrength.key)) },
                            set: { store.set(GeneralBlurStrength.key, String(Int(GeneralBlurStrength.clamp($0)))) }
                        ),
                        in: GeneralBlurStrength.minimum...GeneralBlurStrength.maximum,
                        step: GeneralBlurStrength.step
                    )
                    .frame(width: 180)
                    .accessibilityLabel("Background blur strength")
                    .accessibilityValue("\(Int(blur))")
                }
            }
            card("Notch") {
                row("Hide in full-screen apps", "Hides the notch while the front app is full screen.", "Hide in full-screen apps") {
                    toggle(GeneralFullScreenHiding.key, "Hide in full-screen apps")
                }
                divider
                row(GeneralDrawnShapeLink.title, GeneralDrawnShapeLink.helper, GeneralDrawnShapeLink.accessibilityLabel) {
                    Button("Set in Appearance") {
                        NotificationCenter.default.post(name: .zeusGeneralOpenAppearance, object: nil)
                    }
                    .buttonStyle(GSButtonStyle())
                    .accessibilityLabel(GeneralDrawnShapeLink.accessibilityLabel)
                }
            }
            card("This Mac") {
                row("Menu bar icon", GeneralMenuBarIcon.helper(shown: Preferences.shared.showMenuBarIcon), "Menu bar icon") {
                    Toggle(
                        "Menu bar icon",
                        isOn: Binding(get: { Preferences.shared.showMenuBarIcon }, set: { Preferences.shared.showMenuBarIcon = $0 })
                    )
                    .labelsHidden()
                    .accessibilityLabel("Menu bar icon")
                }
                divider
                row("Haptic feedback", hapticHelper(haptic), "Haptic feedback") {
                    Toggle(
                        "Haptic feedback",
                        isOn: Binding(
                            get: { haptic != .unavailable && store.bool(GeneralHaptics.key) },
                            set: { on in
                                guard haptic != .unavailable else { return }
                                store.set(GeneralHaptics.key, on ? "true" : "false")
                                if GeneralHaptics.plays(GeneralHaptics.readout(loaded: true, storedOn: on, forceTouch: forceTouch, failure: nil)) {
                                    NotchHaptics.action()
                                }
                            }
                        )
                    )
                    .labelsHidden()
                    .allowsHitTesting(haptic != .unavailable)
                    .opacity(haptic == .unavailable ? 0.45 : 1)
                    .accessibilityLabel("Haptic feedback")
                    .accessibilityValue(haptic == .unavailable ? "Unavailable" : (store.bool(GeneralHaptics.key) ? "On" : "Off"))
                }
                if haptic == .loading {
                    Text("Checking the trackpad…")
                        .font(GS.rowText).foregroundStyle(GS.secondary)
                        .accessibilityLabel("Checking the trackpad")
                }
                if haptic == .unavailable {
                    Text("This Mac has no Force Touch trackpad, so haptic feedback stays off.")
                        .font(GS.rowText).foregroundStyle(GS.secondary)
                        .accessibilityLabel("Haptic feedback is unavailable")
                }
            }
            card("Settings") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(chrome.title).font(GS.rowTitle).foregroundStyle(GS.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(chrome.helper).font(GS.rowText).foregroundStyle(GS.secondary)
                        .accessibilityLabel(chrome.accessibilityLabel)
                    if chrome.showsProgress {
                        ProgressView()
                            .accessibilityLabel("Resetting settings")
                    }
                    HStack(spacing: 8) {
                        if let primary = chrome.primaryTitle {
                            Button(primary) { primaryReset(chrome) }
                                .buttonStyle(GSButtonStyle(prominent: reset == .commit))
                                .allowsHitTesting(!chrome.showsProgress)
                                .opacity(chrome.showsProgress ? 0.45 : 1)
                                .accessibilityLabel(chrome.accessibilityLabel)
                        }
                        if let secondary = chrome.secondaryTitle {
                            Button(secondary) { secondaryReset() }
                                .buttonStyle(GSButtonStyle())
                                .accessibilityLabel(secondary)
                        }
                    }
                }
                .frame(minHeight: CGFloat(GlassSettingsMetrics.controlRow), alignment: .leading)
                .accessibilityElement(children: .contain)
            }
        }
        .onAppear {
            forceTouch = GeneralTrackpad.forceTouch
            hapticsLoaded = true
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var store: SettingsStore { .shared }
    private var divider: some View { Rectangle().fill(GS.separator).frame(height: 1) }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GSCard(title) { content() }
            .accessibilityElement(children: .contain)
    }

    private func row<Trailing: View>(_ title: String, _ helper: String, _ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(GS.rowTitle).foregroundStyle(GS.text)
                Text(helper).font(GS.rowText).foregroundStyle(GS.secondary)
                    .frame(minHeight: CGFloat(GlassSettingsMetrics.helperLine), alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label). \(helper)")
            Spacer(minLength: 12)
            trailing()
        }
        .frame(minHeight: CGFloat(GlassSettingsMetrics.controlRow), alignment: .center)
        .accessibilityElement(children: .contain)
    }

    private func toggle(_ key: String, _ label: String) -> some View {
        Toggle(label, isOn: store.boolBinding(key))
            .labelsHidden()
            .accessibilityLabel(label)
    }

    private func previewTile(_ preview: GeneralWindowPreview) -> some View {
        let light = preview.finish == .light
        return VStack(alignment: .leading, spacing: 4) {
            Text(preview.appearance.rawValue).font(GS.rowTitle).foregroundStyle(light ? Color(rgb: 22, 24, 30) : Color(rgb: 241, 243, 248))
            Text(light ? "Light" : "Dark").font(GS.rowText).foregroundStyle(light ? Color(rgb: 96, 102, 114) : Color(rgb: 173, 181, 195))
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(CGFloat(GlassSettingsMetrics.panelPadding) / 2)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(light ? Color(rgb: 244, 245, 248) : Color(rgb: 20, 22, 27)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(preview.accessibilityLabel)
        .animation(Motion.live(MotionTokens.panelResize), value: preview.appearance.rawValue)
    }

    private func hapticHelper(_ readout: GeneralHapticReadout) -> String {
        switch readout {
        case .loading: return "Checking the trackpad…"
        case .unavailable, .failed: return "This Mac has no Force Touch trackpad, so haptic feedback stays off."
        case .off, .on: return "Uses the Force Touch trackpad. Stays off when this Mac has none."
        }
    }

    private func primaryReset(_ chrome: GeneralResetChrome) {
        _ = chrome
        switch reset {
        case .finished:
            reset = GeneralResetConfirmation.transition(reset, .dismiss)
        case .idle, .failed:
            reset = GeneralResetConfirmation.transition(reset, .ask)
        case .review:
            reset = GeneralResetConfirmation.transition(reset, .advance)
        case .commit:
            reset = GeneralResetConfirmation.transition(reset, .commit)
            applyReset()
        case .applying:
            break
        }
    }

    private func secondaryReset() {
        switch reset {
        case .review, .commit:
            reset = GeneralResetConfirmation.transition(reset, .cancel)
        case .failed, .finished:
            reset = GeneralResetConfirmation.transition(reset, .dismiss)
        default:
            break
        }
    }

    private func applyReset() {
        var values: [String: String] = [:]
        var defaults: [String: String] = [:]
        for option in SettingsCatalog.all where option.kind != .action && option.kind != .status && option.state != .custom {
            defaults[option.id] = option.defaultValue
            values[option.id] = store.string(option.id)
        }
        values[GeneralMenuBarIcon.key] = Preferences.shared.showMenuBarIcon ? "true" : "false"
        defaults[GeneralMenuBarIcon.key] = "true"
        let next = GeneralSettingsReset.applying(values: values, defaults: defaults)
        for option in SettingsCatalog.all where defaults[option.id] != nil {
            store.set(option.id, next[option.id] ?? option.defaultValue, origin: .reset)
        }
        if let menu = next[GeneralMenuBarIcon.key] {
            Preferences.shared.showMenuBarIcon = (menu == "true")
        }
        reset = GeneralResetConfirmation.transition(reset, .succeeded)
    }
}

enum GeneralTrackpad {
    static var forceTouch: Bool {
        guard let match = IOServiceMatching("AppleMultitouchDevice") else { return false }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        var supported = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let raw = IORegistryEntryCreateCFProperty(service, "ForceSupported" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { continue }
            if (raw as? Bool) == true || (raw as? NSNumber)?.boolValue == true { supported = true }
        }
        return supported
    }
}
