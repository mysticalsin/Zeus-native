import AppKit
import SwiftUI
import ZeusCore

extension LicenseSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(LicenseSettingsSection()) }
}

/// The license card hosted on the existing License page.
struct LicenseSettingsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var machine = LicenseActivationState(phase: .unlicensed, facts: LicenseCardFacts(status: .trialEnded))
    @FocusState private var keyFocused: Bool
    private var license: LicenseManager { .shared }

    var body: some View {
        let presentation = LicenseCardPresentation.make(machine)
        let motion = presentation.motion.duration == 0 || reduceMotion
        VStack(alignment: .leading, spacing: presentation.cardSpacing) {
            GSCard("License") {
                preview(presentation)
                if presentation.empty {
                    Text("No license on this Mac yet.")
                        .font(GS.rowText).foregroundStyle(GS.secondary)
                        .accessibilityLabel("No license on this Mac yet. \(presentation.preview.detail)")
                        .padding(.bottom, 8)
                }
            }
            GSCard("This Mac") {
                let rows = presentation.controls.filter { $0.id != "glass.license.status" }
                ForEach(Array(rows.enumerated()), id: \.offset) { pair in
                    if pair.offset > 0 { GSDivider() }
                    controlRow(pair.element, presentation: presentation)
                }
            }
            if let announcement = machine.copiedAnnouncement {
                Text(announcement)
                    .font(GS.rowText).foregroundStyle(GS.secondary)
                    .accessibilityLabel(announcement)
            }
        }
        .padding(presentation.panelPadding)
        .animation(motion ? nil : .easeOut(duration: presentation.motion.duration), value: machine.phase)
        .accessibilityElement(children: .contain)
        .task { sync() }
        .onChange(of: reduceMotion) { _, _ in sync() }
        .onChange(of: license.status) { _, _ in sync() }
        .onChange(of: license.lastError) { _, _ in sync() }
        .onChange(of: license.deactivationError) { _, _ in sync() }
        .onChange(of: license.activationPending) { _, _ in sync() }
        .onChange(of: license.busy) { _, _ in sync() }
    }

    private func preview(_ presentation: LicenseCardPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(presentation.preview.badge)
                    .font(GS.rowTitle).foregroundStyle(GS.text)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.preview.title).font(GS.rowTitle).foregroundStyle(GS.text)
                    Text(presentation.preview.detail).font(GS.rowText).foregroundStyle(GS.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            .frame(minHeight: presentation.rowHeight, alignment: .center)
            progress(presentation.preview.progress)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.preview.accessibilityLabel)
    }

    private func progress(_ amount: Double) -> some View {
        Capsule()
            .fill(GS.window)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(GS.selectedText)
                    .scaleEffect(x: min(max(amount, 0), 1), anchor: .leading)
            }
    }

    @ViewBuilder
    private func controlRow(_ control: LicenseCardControl, presentation: LicenseCardPresentation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                Text(control.title).font(GS.rowTitle).foregroundStyle(GS.text)
                Spacer(minLength: 12)
                trailing(control)
            }
            Text(control.helper)
                .font(GS.rowText).foregroundStyle(GS.secondary)
                .frame(minHeight: presentation.helperLine, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .frame(minHeight: presentation.rowHeight, alignment: .center)
        .padding(.vertical, 6)
        .accessibilityIdentifier(control.id)
    }

    @ViewBuilder
    private func trailing(_ control: LicenseCardControl) -> some View {
        if control.id == "glass.license.key" || control.id == "glass.license.draft" {
            keyField(control)
        } else if let event = control.event {
            Button(control.title) { perform(event) }
                .buttonStyle(GSButtonStyle(prominent: control.id == "glass.license.activate" || control.id == "glass.license.purchase"))
                .disabled(!control.enabled)
                .accessibilityLabel(control.accessibilityLabel)
                .accessibilityHint(control.helper)
        }
    }

    @ViewBuilder
    private func keyField(_ control: LicenseCardControl) -> some View {
        let editable = control.id == "glass.license.draft" || machine.enteringReplacement || machine.facts.storedKey.isEmpty
        if editable {
            let binding = Binding<String>(
                get: { machine.draft.reveal() },
                set: { perform(.editDraft($0)) }
            )
            Group {
                if control.revealsKey {
                    TextField("License key", text: binding)
                } else {
                    SecureField("License key", text: binding)
                }
            }
            .textFieldStyle(.plain)
            .snapshotSafeText(binding.wrappedValue, placeholder: "License key", secure: !control.revealsKey)
            .font(OB.font(13.5)).foregroundStyle(GS.text)
            .frame(width: 220, height: 34)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GS.window))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
            .focused($keyFocused)
            .disabled(!control.enabled)
            .accessibilityLabel(control.accessibilityLabel)
            .accessibilityHint(control.helper)
            .onSubmit { perform(.activate) }
        } else {
            Text(control.accessibilityValue)
                .font(OB.font(13.5)).foregroundStyle(GS.text)
                .lineLimit(1)
                .accessibilityLabel(control.accessibilityLabel)
                .accessibilityValue(control.accessibilityValue)
                .accessibilityHint(control.helper)
        }
    }

    private func sync() {
        perform(.setReduceMotion(reduceMotion || Motion.reduced))
        perform(.replaceFacts(LicenseSettingsBridge.facts(from: license)))
        LicenseSettingsBridge.publish(phase: machine.phase)
    }

    private func perform(_ event: LicenseActivationEvent) {
        let (next, effects) = LicenseActivationMachine.step(machine, event)
        machine = next
        for effect in effects {
            switch effect {
            case .activateOnThisMac(let draft):
                let key = draft.normalized
                Task {
                    let message = await license.activate(key)
                    perform(.activationFinished(LicenseSettingsBridge.facts(from: license), message: message))
                }
            case .releaseThisMac:
                Task {
                    let message = await license.deactivate()
                    perform(.releaseFinished(LicenseSettingsBridge.facts(from: license), message: message))
                }
            case .copyKey(let draft):
                let value = draft.normalized
                guard !value.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            case .showPurchaseNote:
                keyFocused = true
            }
        }
    }
}
