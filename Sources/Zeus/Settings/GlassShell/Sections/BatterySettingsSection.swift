import AppKit
import SwiftUI
import ZeusCore

extension BatterySectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(BatterySettingsSection()) }
}

struct BatterySettingsSection: View {
    @State private var consent = EarbudConsent.State()
    @State private var hasRead = false
    @State private var note = ""

    private var lightsOn: Bool { SettingsStore.shared.bool(BatteryLightsSetting.key) }
    private var style: BatteryOverlayStyle { BatteryOverlayStyle.resolve(SettingsStore.shared.string(BatteryOverlayStyle.storageKey)) }
    private var earbudsOn: Bool { SettingsStore.shared.bool(BatteryEarbudSetting.key) }
    private var reduceMotion: Bool { Motion.reduced }

    var body: some View {
        let model = BatteryPreview.make(
            observation: observation,
            preferences: BatteryPreferences(lightsEnabled: lightsOn, style: style, earbudsEnabled: earbudsOn),
            earbud: nil,
            reduceMotion: reduceMotion
        )
        ScrollView {
            VStack(alignment: .leading, spacing: BatterySectionMetrics.cardGap) {
                overlayCard
                    .accessibilitySortPriority(3)
                earbudCard
                    .accessibilitySortPriority(2)
                preview(model)
                    .accessibilitySortPriority(1)
            }
            .padding(BatterySectionMetrics.panelPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .onAppear(perform: appear)
    }

    private var observation: BatteryPowerObservation {
        let reading = PowerMonitor.shared.power
        guard hasRead || PowerMonitor.shared.isRunning else { return .loading }
        guard let percent = reading.batteryPercent else { return .noBattery }
        return .battery(BatteryPowerSample(percent: percent, charging: reading.isCharging, onAC: !reading.onBattery))
    }

    private var overlayCard: some View {
        card("Charge") {
            toggleRow(BatterySectionCopy.controls[0], isOn: lightsBinding)
            VStack(alignment: .leading, spacing: 6) {
                Text(BatterySectionCopy.controls[1].title)
                    .font(GS.rowTitle)
                    .foregroundStyle(GS.text)
                HStack(spacing: 8) {
                    ForEach(BatteryOverlayStyle.allCases, id: \.self) { item in
                        Button(item.title) { SettingsStore.shared.set(BatteryOverlayStyle.storageKey, item.rawValue) }
                            .buttonStyle(GSButtonStyle(prominent: item == style))
                            .accessibilityLabel(item.accessibilityLabel)
                            .accessibilityAddTraits(item == style ? .isSelected : [])
                    }
                }
                helper(BatterySectionCopy.controls[1].helper)
            }
            .frame(minHeight: BatterySectionMetrics.rowHeight, alignment: .center)
            .accessibilityElement(children: .contain)
            .accessibilityHint(BatterySectionCopy.controls[1].helper)
        }
    }

    private var earbudCard: some View {
        card("Earbuds") {
            toggleRow(BatterySectionCopy.controls[2], isOn: earbudBinding)
            if consent.phase == .waiting {
                Button("Allow") { turnEarbuds(true) }
                    .buttonStyle(GSButtonStyle())
                    .accessibilityLabel("Allow Bluetooth for earbud battery")
                helper("Asks for Bluetooth only from this button.")
            }
            if consent.phase == .prompting {
                helper("macOS will ask to let Zeus use Bluetooth.")
            }
            if consent.phase == .denied {
                helper("Bluetooth is not allowed.")
                Button("Open System Settings") { openBluetoothSettings() }
                    .buttonStyle(GSButtonStyle())
                    .accessibilityLabel("Open System Settings for Bluetooth")
            }
            if !note.isEmpty { helper(note) }
        }
    }

    private func preview(_ model: BatteryPreviewModel) -> some View {
        card(BatterySectionCopy.previewTitle) {
            previewBody(model)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(model.ringLabel)
                .accessibilityIdentifier("battery.preview")
            helper(BatterySectionCopy.previewHelper)
            HStack(spacing: 16) {
                ForEach(model.earbuds, id: \.title) { part in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(part.title).font(GS.rowTitle).foregroundStyle(GS.text)
                        Text(part.text).font(GS.rowText).foregroundStyle(GS.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(part.accessibilityLabel)
                }
            }
        }
    }

    @ViewBuilder
    private func previewBody(_ model: BatteryPreviewModel) -> some View {
        switch model.load {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text(BatterySectionCopy.loadingLabel).font(GS.rowText).foregroundStyle(GS.secondary)
            }
            .frame(minHeight: BatterySectionMetrics.rowHeight, alignment: .leading)
            .accessibilityLabel(BatterySectionCopy.loadingLabel)
        case .empty:
            VStack(alignment: .leading, spacing: 4) {
                Text(BatterySectionCopy.emptyTitle).font(GS.rowTitle).foregroundStyle(GS.text)
                Text(BatterySectionCopy.emptyHelper).font(GS.rowText).foregroundStyle(GS.secondary)
            }
            .frame(minHeight: BatterySectionMetrics.rowHeight, alignment: .leading)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(GS.rowTitle).foregroundStyle(GS.text)
                Button("Try again") { readPower() }
                    .buttonStyle(GSButtonStyle())
                    .accessibilityLabel("Try reading the battery again")
            }
        case .ready:
            HStack(spacing: 18) {
                ring(model)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.ringLabel).font(GS.rowTitle).foregroundStyle(GS.text)
                    Text(model.style.title).font(GS.rowText).foregroundStyle(GS.secondary)
                }
            }
            .frame(minHeight: BatterySectionMetrics.rowHeight, alignment: .leading)
        }
    }

    private func ring(_ model: BatteryPreviewModel) -> some View {
        let fraction = model.ringFraction ?? 0
        return ZStack {
            Circle().stroke(GS.separator, lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(GS.selectedText, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.reducible(.easeInOut(duration: model.animationDuration), reduceMotion: model.reduceMotion), value: fraction)
            Text(model.ringFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "")
                .font(GS.rowText)
                .foregroundStyle(GS.text)
                .accessibilityHidden(true)
        }
        .frame(width: 52, height: 52)
        .accessibilityLabel(model.ringLabel)
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

    private func toggleRow(_ copy: BatteryControlCopy, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: isOn) {
                Text(copy.title).font(GS.rowTitle).foregroundStyle(GS.text)
            }
            .toggleStyle(.switch)
            .accessibilityLabel(copy.accessibilityLabel)
            .accessibilityHint(copy.helper)
            helper(copy.helper)
        }
        .frame(minHeight: BatterySectionMetrics.rowHeight, alignment: .center)
    }

    private func helper(_ text: String) -> some View {
        Text(text)
            .font(GS.rowText)
            .foregroundStyle(GS.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    private var lightsBinding: Binding<Bool> {
        Binding(
            get: { lightsOn },
            set: { SettingsStore.shared.set(BatteryLightsSetting.key, $0 ? "true" : "false") }
        )
    }

    private var earbudBinding: Binding<Bool> {
        Binding(get: { earbudsOn }, set: { turnEarbuds($0) })
    }

    private func appear() {
        PowerMonitor.shared.start(for: .batteryOverlay)
        let enabled = SettingsStore.shared.bool(BatteryEarbudSetting.key)
        let access = BatteryBluetoothPrompt.current()
        consent = EarbudConsent.reduce(.init(), .restore(enabled: enabled, access: access)).0
        readPower()
    }

    private func readPower() {
        PowerMonitor.shared.refresh()
        hasRead = true
    }

    private func turnEarbuds(_ on: Bool) {
        let currently = earbudsOn
        let enabled = BatteryEarbudSetting.enabled(requested: on, origin: .person, currently: currently)
        let access = BatteryBluetoothPrompt.current()
        let (next, effects) = EarbudConsent.reduce(consent, .userSet(enabled: enabled, access: access))
        consent = next
        SettingsStore.shared.set(BatteryEarbudSetting.key, enabled ? "true" : "false")
        note = ""
        guard effects.contains(.promptForBluetooth) else { return }
        BatteryBluetoothPrompt.ask { access in
            Task { @MainActor in
                let (answered, _) = EarbudConsent.reduce(consent, .accessAnswered(access))
                consent = answered
                if access != .allowed {
                    note = "Bluetooth is not allowed."
                }
            }
        }
    }

    private func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") else { return }
        NSWorkspace.shared.open(url)
    }
}
