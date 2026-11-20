import SwiftUI
import ZeusCore

extension SensorySectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(SensorySettingsSection()) }
}

/// Volume and brightness overlay. The slot stays unfilled until the shell can place it with `.topbarTab(7)`.
struct SensorySettingsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reading = true
    @State private var snapshot = SensoryHUDSnapshot.hidden
    @State private var now = Date()
    @State private var previewRun = 0

    private var store: SettingsStore { SettingsStore.shared }

    var body: some View {
        let settings = SensorySettings.read { store.string($0) }
        let trusted = AccessibilityGate.trusted
        let rows = SensoryControls.rows(settings, trusted: trusted)
        let frame = SensoryPreview.frame(
            settings: settings, trusted: trusted, reading: reading,
            snapshot: snapshot, now: now, reduceMotion: reduceMotion
        )
        let motion = SensoryLayout.animationDuration(reduceMotion: reduceMotion)
        VStack(alignment: .leading, spacing: SensoryLayout.cardSpacing) {
            previewCard(frame, motion: motion)
            card("Overlay") {
                toggle(row(SensorySettings.volumeKey, in: rows), key: SensorySettings.volumeKey)
                divider
                toggle(row(SensorySettings.brightnessKey, in: rows), key: SensorySettings.brightnessKey)
                divider
                toggle(row(SensorySettings.replaceSystemKey, in: rows), key: SensorySettings.replaceSystemKey)
            }
            card("How it appears") {
                hold(row(SensorySettings.holdKey, in: rows))
                divider
                labelPicker(row(SensorySettings.labelKey, in: rows))
                divider
                previewButton(row(SensoryControls.previewID, in: rows))
            }
        }
        .padding(SensoryLayout.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { reading = false }
        .task(id: previewRun) { await playPreview(settings: settings) }
    }

    private func row(_ id: String, in rows: [SensoryControl]) -> SensoryControl {
        rows.first { $0.id == id } ?? SensoryControl(
            id: id, title: id, helper: "", accessibilityLabel: id, accessibilityValue: "", keyboardReachable: true
        )
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(GS.cardTitle)
                .foregroundStyle(GS.text)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).fill(GS.card))
        .overlay(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
    }

    private var divider: some View { Rectangle().fill(GS.separator).frame(height: 1) }

    private func toggle(_ model: SensoryControl, key: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Text(model.title).font(GS.rowTitle).foregroundStyle(GS.text)
                Spacer(minLength: 12)
                Toggle(model.accessibilityLabel, isOn: store.boolBinding(key))
                    .toggleStyle(GSToggleStyle())
                    .labelsHidden()
                    .accessibilityLabel(model.accessibilityLabel)
                    .accessibilityValue(model.accessibilityValue)
                    .accessibilityHint(model.helper)
            }
            .frame(minHeight: SensoryLayout.rowHeight)
            helper(model.helper)
        }
    }

    private func hold(_ model: SensoryControl) -> some View {
        let value = Binding<Double>(
            get: { SensoryHUDHold.parse(store.string(SensorySettings.holdKey)) },
            set: { proposed in
                let current = SensoryHUDHold.parse(store.string(SensorySettings.holdKey))
                let direction = proposed > current ? 1 : proposed < current ? -1 : 0
                store.set(SensorySettings.holdKey, SensoryHUDHold.store(SensoryHUDHold.step(current, direction: direction)))
            }
        )
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Text(model.title).font(GS.rowTitle).foregroundStyle(GS.text)
                Spacer(minLength: 12)
                Stepper(value: value, in: SensoryHUDHold.minimum...SensoryHUDHold.maximum, step: SensoryHUDHold.step) {
                    Text("\(SensoryHUDHold.store(value.wrappedValue)) s")
                        .font(GS.rowTitle.monospacedDigit())
                        .foregroundStyle(GS.text)
                }
                .accessibilityLabel(model.accessibilityLabel)
                .accessibilityValue(model.accessibilityValue)
                .accessibilityHint(model.helper)
            }
            .frame(minHeight: SensoryLayout.rowHeight)
            helper(model.helper)
        }
    }

    private func labelPicker(_ model: SensoryControl) -> some View {
        let selection = Binding<SensoryHUDLabel>(
            get: { SensoryHUDLabel.parse(store.string(SensorySettings.labelKey)) },
            set: { store.set(SensorySettings.labelKey, $0.rawValue) }
        )
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Text(model.title).font(GS.rowTitle).foregroundStyle(GS.text)
                Spacer(minLength: 12)
                Picker(model.accessibilityLabel, selection: selection) {
                    Text("Icon").tag(SensoryHUDLabel.icon)
                    Text("Words").tag(SensoryHUDLabel.words)
                }
                .pickerStyle(.segmented)
                .frame(width: 168)
                .accessibilityLabel(model.accessibilityLabel)
                .accessibilityValue(model.accessibilityValue)
                .accessibilityHint(model.helper)
            }
            .frame(minHeight: SensoryLayout.rowHeight)
            helper(model.helper)
        }
    }

    private func previewButton(_ model: SensoryControl) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Text(model.title).font(GS.rowTitle).foregroundStyle(GS.text)
                Spacer(minLength: 12)
                Button(model.accessibilityValue) { previewRun += 1 }
                    .buttonStyle(GSButtonStyle())
                    .accessibilityLabel(model.accessibilityLabel)
                    .accessibilityHint(model.helper)
            }
            .frame(minHeight: SensoryLayout.rowHeight)
            helper(model.helper)
        }
    }

    private func helper(_ text: String) -> some View {
        Text(text)
            .font(GS.rowText)
            .foregroundStyle(GS.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
    }

    private func previewCard(_ frame: SensoryPreviewFrame, motion: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(GS.cardTitle)
                .foregroundStyle(GS.text)
                .accessibilityAddTraits(.isHeader)
            Group {
                switch frame.status {
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(frame.title).font(GS.rowTitle).foregroundStyle(GS.text)
                    }
                case .empty:
                    Text(frame.title).font(GS.rowTitle).foregroundStyle(GS.text)
                    Text(frame.detail).font(GS.rowText).foregroundStyle(GS.secondary)
                case .live:
                    HStack(spacing: 10) {
                        if let symbol = frame.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(GS.text)
                                .opacity(frame.opacity)
                                .accessibilityHidden(true)
                        }
                        Text(frame.words ?? frame.detail)
                            .font(GS.rowTitle.monospacedDigit())
                            .foregroundStyle(GS.text)
                            .opacity(frame.words == nil && frame.symbol != nil ? 1 : frame.opacity)
                    }
                    .animation(motion == 0 ? nil : .easeOut(duration: motion), value: frame.opacity)
                    Text(frame.title).font(GS.rowText).foregroundStyle(GS.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            if let error = frame.error {
                Text(error)
                    .font(GS.rowText)
                    .foregroundStyle(GS.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).fill(GS.card))
        .overlay(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(frame.error.map { "\(frame.title). \($0)" } ?? frame.title)
    }

    private func playPreview(settings: SensorySettings) async {
        guard previewRun > 0 else { return }
        let config = SensoryHUDConfig(settings: settings, reduceMotion: reduceMotion)
        guard let event = SensoryHUDLifecycle.sampleChange(settings: settings, at: Date()) else {
            snapshot = .hidden
            return
        }
        var state = SensoryHUDSnapshot.hidden
        let (shown, _) = SensoryHUDLifecycle.reduce(state, event, config: config)
        state = shown
        snapshot = state
        if case .changed(_, _, _, let at) = event { now = at }
        while !Task.isCancelled, state.phase != .hidden {
            let moment = Date()
            let remaining = SensoryHUDLifecycle.timeUntilHidden(state, now: moment, config: config)
            if remaining <= 0 {
                let (next, _) = SensoryHUDLifecycle.reduce(state, .tick(moment), config: config)
                state = next
                snapshot = state
                now = moment
                break
            }
            let slice = reduceMotion ? remaining : min(0.05, remaining)
            try? await Task.sleep(for: .seconds(slice))
            if Task.isCancelled { return }
            let tick = Date()
            let (next, _) = SensoryHUDLifecycle.reduce(state, .tick(tick), config: config)
            state = next
            snapshot = state
            now = tick
        }
    }
}
