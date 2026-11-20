import SwiftUI
import ZeusCore

extension AccessorySectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(AccessorySettingsSection()) }
}

/// Accessory settings. Earbud charge is an injected `AccessoryConnectInput`; this page does not read a radio.
struct AccessorySettingsSection: View {
    var earbud: AccessoryConnectInput?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var controller = AccessorySectionController()

    init(earbud: AccessoryConnectInput? = nil) {
        self.earbud = earbud
    }

    var body: some View {
        let motion = reduceMotion
        ScrollView {
            VStack(alignment: .leading, spacing: CGFloat(GlassSettingsMetrics.cardSpacing)) {
                overlayCard
                styleCard
                speakerCard
                previewCard
            }
            .padding(CGFloat(GlassSettingsMetrics.panelPadding))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            controller.restore()
            controller.apply(.reduceMotion(motion))
            deliver(earbud)
        }
        .onChange(of: reduceMotion) { _, value in
            controller.apply(.reduceMotion(value))
        }
        .onChange(of: earbud) { _, value in
            deliver(value)
        }
        .animation(motion ? nil : .easeOut(duration: controller.model.preview.duration), value: controller.model.preferences)
        .animation(motion ? nil : .easeOut(duration: controller.model.preview.duration), value: controller.model.overlay.phase)
        .animation(motion ? nil : .easeOut(duration: controller.model.preview.duration), value: controller.model.speakers.phase)
    }

    private var overlayCard: some View {
        card("Earbuds") {
            row(AccessoryCopy.earbuds) {
                Toggle(AccessoryCopy.earbuds.accessibilityLabel, isOn: Binding(
                    get: { controller.model.preferences.earbudsOverlay },
                    set: { controller.apply(.setEarbudsOverlay($0)) }
                ))
                .labelsHidden()
                .accessibilityLabel(AccessoryCopy.earbuds.accessibilityLabel)
                .accessibilityHint(AccessoryCopy.earbuds.accessibilityHint)
            }
        }
    }

    private var styleCard: some View {
        card("Style") {
            row(AccessoryCopy.style) {
                Picker(AccessoryCopy.style.accessibilityLabel, selection: Binding(
                    get: { controller.model.preferences.overlayStyle },
                    set: { controller.apply(.setOverlayStyle($0)) }
                )) {
                    ForEach(AccessoryOverlayStyle.allCases, id: \.self) { style in
                        Text(AccessoryCopy.styleChoice(style)).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(AccessoryCopy.style.accessibilityLabel)
                .accessibilityHint(AccessoryCopy.style.accessibilityHint)
            }
        }
    }

    private var speakerCard: some View {
        card("Speakers") {
            row(AccessoryCopy.speakers) {
                Toggle(AccessoryCopy.speakers.accessibilityLabel, isOn: Binding(
                    get: { controller.model.preferences.speakerNames },
                    set: { enabled in
                        if enabled { controller.apply(.askToEnableSpeakers) }
                        else { controller.apply(.disableSpeakers) }
                    }
                ))
                .labelsHidden()
                .accessibilityLabel(AccessoryCopy.speakers.accessibilityLabel)
                .accessibilityHint(AccessoryCopy.speakers.accessibilityHint)
            }
            if controller.model.confirmation == .enableSpeakers {
                Text(AccessoryCopy.enableConfirmation)
                    .font(.callout)
                    .foregroundStyle(GS.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(AccessoryCopy.enableConfirmation)
                HStack(spacing: 12) {
                    Button(AccessoryCopy.confirm) { controller.apply(.confirmSpeakerEnable) }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel(AccessoryCopy.confirm)
                        .accessibilityHint(AccessoryCopy.enableConfirmation)
                    Button(AccessoryCopy.cancel) { controller.apply(.cancelSpeakerEnable) }
                        .accessibilityLabel(AccessoryCopy.cancel)
                        .accessibilityHint(AccessoryCopy.enableConfirmation)
                }
            }
            speakerStatus
        }
    }

    @ViewBuilder
    private var speakerStatus: some View {
        let phase = controller.model.speakers.phase
        if phase.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(phase.status)
                Text(phase.status)
                    .foregroundStyle(GS.secondary)
            }
            .frame(minHeight: CGFloat(GlassSettingsMetrics.controlRow), alignment: .leading)
            .accessibilityElement(children: .combine)
            .focusable(true)
        } else {
            Text(controller.model.speakerStatus)
                .font(.callout)
                .foregroundStyle(GS.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(phase.accessibilityLabel)
                .focusable(true)
        }
        if case .names(let speakers) = phase {
            ForEach(speakers) { speaker in
                Text(speaker.displayName)
                    .foregroundStyle(GS.text)
                    .frame(minHeight: CGFloat(GlassSettingsMetrics.controlRow), alignment: .leading)
                    .accessibilityLabel(speaker.name)
                    .accessibilityHint("Nearby speaker.")
                    .focusable(true)
            }
        }
        if phase.isUnavailable {
            Button("Local network settings") {
                NSWorkspace.shared.open(FlingService.localNetworkSettingsURL)
            }
            .accessibilityLabel("Local network settings")
            .accessibilityHint(phase.status)
        }
        if phase.isError {
            Button("Try again") { controller.apply(.askToEnableSpeakers) }
                .accessibilityLabel("Try again")
                .accessibilityHint(phase.status)
        }
        if controller.model.preferences.speakerNames, phase == .off, controller.model.confirmation == .idle {
            Button("Look for speakers") { controller.apply(.askToEnableSpeakers) }
                .accessibilityLabel("Look for speakers")
                .accessibilityHint(AccessoryCopy.enableConfirmation)
        }
    }

    private var previewCard: some View {
        let preview = controller.model.preview
        return card("Preview") {
            VStack(alignment: .leading, spacing: 8) {
                if preview.visible {
                    Text(preview.title)
                        .font(GS.rowTitle)
                        .foregroundStyle(GS.text)
                    ForEach(preview.lines, id: \.self) { line in
                        Text(line)
                            .foregroundStyle(GS.secondary)
                    }
                } else {
                    Text(preview.emptyMessage)
                        .foregroundStyle(GS.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: CGFloat(GlassSettingsMetrics.controlRow), alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(GS.window.opacity(0.55))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(preview.visible ? preview.accessibilityLabel : preview.emptyMessage)
            .accessibilityHint(AccessoryCopy.previewOff)
            .focusable(true)
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(GS.cardTitle)
                .foregroundStyle(GS.text)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).fill(GS.card))
        .overlay(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
    }

    private func row<Control: View>(_ copy: AccessoryControlCopy, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                Text(copy.title)
                    .foregroundStyle(GS.text)
                Spacer(minLength: 12)
                control()
            }
            .frame(minHeight: CGFloat(GlassSettingsMetrics.controlRow))
            Text(copy.helper)
                .font(.callout)
                .foregroundStyle(GS.secondary)
                .frame(minHeight: CGFloat(GlassSettingsMetrics.helperLine), alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .focusable(true)
    }

    private func deliver(_ input: AccessoryConnectInput?) {
        if let input, input.connected {
            controller.apply(.earbudsConnected(input))
        } else {
            controller.apply(.earbudsDisconnected)
        }
    }
}

@MainActor
final class AccessorySectionController: ObservableObject {
    @Published private(set) var model = AccessorySectionModel()
    private let browser = AccessorySpeakerBrowser()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restore() {
        apply(.restore(
            overlay: defaults.string(forKey: AccessoryPreferenceKey.earbudsOverlay),
            style: defaults.string(forKey: AccessoryPreferenceKey.overlayStyle),
            speakers: defaults.string(forKey: AccessoryPreferenceKey.speakerNames)
        ))
    }

    func apply(_ event: AccessorySectionEvent) {
        var next = model
        let effects = next.handle(event)
        model = next
        for effect in effects {
            switch effect {
            case .persist(let preferences):
                defaults.set(preferences.earbudsOverlay ? "true" : "false", forKey: AccessoryPreferenceKey.earbudsOverlay)
                defaults.set(preferences.overlayStyle.rawValue, forKey: AccessoryPreferenceKey.overlayStyle)
                defaults.set(preferences.speakerNames ? "true" : "false", forKey: AccessoryPreferenceKey.speakerNames)
            case .requestPermission, .startSearch:
                browser.start { [weak self] signal in
                    Task { @MainActor in
                        self?.consume(signal)
                    }
                }
            case .stopSearch:
                browser.stop()
            case .overlay:
                break
            }
        }
    }

    private func consume(_ signal: NearbySpeakerBrowserSignal) {
        let events = NearbySpeakerBrowserRules.events(
            dnsCode: signal == .denied ? NearbySpeakerBrowserRules.deniedDNSCode : nil,
            failed: signal == .failed,
            ready: signal == .ready,
            names: {
                if case .results(let names) = signal { return names }
                return nil
            }()
        )
        for event in events {
            switch event {
            case .permissionAllowed: apply(.permissionAllowed)
            case .permissionDenied: apply(.permissionDenied)
            case .searchFailed: apply(.searchFailed)
            case .found(let names): apply(.speakersFound(names))
            case .userEnabled, .userDisabled, .permissionRestricted:
                break
            }
        }
    }
}
