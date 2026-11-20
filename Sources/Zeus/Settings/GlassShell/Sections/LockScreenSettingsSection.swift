import SwiftUI
import ZeusCore

extension LockScreenSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(LockScreenSettingsSection()) }
}

/// Lock Screen settings. The preview is read-only, and every control explains itself.
struct LockScreenSettingsSection: View {
    private var store: SettingsStore { .shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loaded = false
    @State private var space: LockScreenSpaceAnswer?

    var body: some View {
        let settings = resolved
        let model = LockScreenPageModel.make(
            settings: settings,
            playback: settings.playerCard && space == nil ? .playing : .none,
            space: settings.playerCard ? space : nil,
            reduceMotion: reduceMotion,
            soundFileExists: LockScreenCuePlayer.exists,
            loaded: loaded
        )
        VStack(alignment: .leading, spacing: GlassSettingsMetrics.cardSpacing) {
            preview(model)
            if model.phase != .loading {
                card("Lock screen") {
                    labeledRow(model.controls[0]) {
                        Toggle(model.controls[0].title, isOn: store.boolBinding(LockScreenSettingKey.playerCard))
                            .toggleStyle(LockScreenSwitch(duration: model.animationDuration))
                            .labelsHidden()
                            .accessibilityLabel(model.controls[0].label)
                            .accessibilityHint(model.controls[0].helper)
                            .accessibilityValue(model.controls[0].value)
                    }
                    if case .unavailable(let text) = model.phase {
                        Text(text)
                            .font(GS.rowText)
                            .foregroundStyle(GS.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(text)
                    }
                }
                card("Sounds") {
                    soundRow(model.controls[1], selection: store.stringBinding(LockScreenSettingKey.lockSound), options: LockScreenSoundOption.all.map(\.title), moment: .lock)
                    soundRow(model.controls[2], selection: store.stringBinding(LockScreenSettingKey.unlockSound), options: LockScreenSoundOption.all.map(\.title), moment: .unlock)
                    soundRow(model.controls[3], selection: store.stringBinding(LockScreenSettingKey.soundLevel), options: LockScreenSoundLevel.allCases.map(\.rawValue), moment: nil)
                    if let note = model.soundNote {
                        Text(note)
                            .font(GS.rowText)
                            .foregroundStyle(GS.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(note)
                    }
                }
            }
        }
        .padding(GlassSettingsMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(model.animationDuration == 0 ? nil : .easeOut(duration: model.animationDuration), value: resolved)
        .onAppear {
            loaded = true
            refresh()
        }
        .onChange(of: resolved) { _, _ in refresh() }
    }

    private var resolved: LockScreenSettings {
        LockScreenSettingsStore(values: Dictionary(uniqueKeysWithValues: LockScreenSettingKey.all.map { ($0, store.string($0)) })).settings
    }

    private func refresh() {
        space = resolved.playerCard ? LockScreenSpaceLoader.probe() : nil
        LockScreenCoordinator.shared.sync(resolved)
    }

    private func preview(_ model: LockScreenPageModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(GS.cardTitle)
                .foregroundStyle(GS.text)
                .accessibilityAddTraits(.isHeader)
            switch model.preview.body {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: model.rowHeight, alignment: .leading)
            case .empty(let text), .unavailable(let text):
                Text(text)
                    .font(GS.rowText)
                    .foregroundStyle(GS.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .card(let word):
                Text(word)
                    .font(GS.rowTitle)
                    .foregroundStyle(GS.text)
                Text("Read only")
                    .font(GS.rowText)
                    .foregroundStyle(GS.secondary)
            }
        }
        .padding(GS.cardInset)
        .frame(maxWidth: .infinity, minHeight: model.rowHeight, alignment: .leading)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.preview.accessibilityLabel)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(GS.cardTitle)
                .foregroundStyle(GS.text)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(GS.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous)
            .fill(GS.card)
            .overlay(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
    }

    private func labeledRow<Trailing: View>(_ control: LockScreenControl, @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                Text(control.title)
                    .font(GS.rowTitle)
                    .foregroundStyle(GS.text)
                    .accessibilityHidden(true)
                Spacer(minLength: 12)
                trailing()
            }
            .frame(minHeight: GlassSettingsMetrics.controlRow)
            Text(control.helper)
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: GlassSettingsMetrics.helperLine, alignment: .leading)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    private func soundRow(
        _ control: LockScreenControl,
        selection: Binding<String>,
        options: [String],
        moment: LockScreenMoment?
    ) -> some View {
        labeledRow(control) {
            HStack(spacing: 8) {
                Picker(control.title, selection: selection) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel(control.label)
                .accessibilityHint(control.helper)
                .accessibilityValue(control.value)
                if let moment {
                    Button("Play") { playPreview(moment) }
                        .buttonStyle(GSButtonStyle())
                        .accessibilityLabel("Play \(control.title)")
                        .accessibilityHint(control.helper)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func playPreview(_ moment: LockScreenMoment) {
        let cue = LockScreenSounds.cue(
            settings: resolved,
            from: moment == .lock ? .locking : .unlocking,
            to: moment == .lock ? .locked : .unlocked,
            fileExists: LockScreenCuePlayer.exists
        )
        LockScreenCuePlayer.play(cue)
    }
}

/// The switch moves only when Reduce Motion is off.
private struct LockScreenSwitch: ToggleStyle {
    var duration: Double

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? OB.toggleOn : GS.toggleOff)
                    .frame(width: 44, height: 20)
                Capsule()
                    .fill(GS.knob)
                    .frame(width: 27, height: 16)
                    .padding(.horizontal, 2)
            }
            .animation(duration == 0 ? nil : .easeOut(duration: duration), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}
