import SwiftUI
import ZeusCore

extension AutoUpdateSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(AutoUpdateSettingsSection()) }
}

/// Updates card. It merges onto About at card order 1 and does not open another window.
struct AutoUpdateSettingsSection: View {
    @State private var session = UpdatesSessionModel()

    var body: some View {
        let card = session.card
        VStack(alignment: .leading, spacing: CGFloat(card.cardSpacing)) {
            preview(card)
            GSCard(card.title) {
                status(card)
                ForEach(card.rows) { row in
                    control(row, height: CGFloat(card.rowHeight))
                    if row.id != card.rows.last?.id { GSDivider() }
                }
                notes(card)
                confirmation
            }
        }
        .animation(card.animationDuration == 0 ? nil : .easeOut(duration: card.animationDuration), value: session.state)
        .onAppear { session.appear() }
        .onDisappear { SignedUpdateBridge.shared.cancel() }
        .accessibilityElement(children: .contain)
    }

    private func preview(_ card: UpdatesCardModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(GS.cardTitle)
                .foregroundStyle(GS.text)
                .accessibilityAddTraits(.isHeader)
            Text(card.preview.versionLine)
                .font(GS.rowTitle)
                .foregroundStyle(GS.text)
                .monospacedDigit()
            Text(card.preview.statusLine)
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if card.showsIndeterminateMotion {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking")
            }
        }
        .frame(maxWidth: .infinity, minHeight: CGFloat(card.rowHeight), alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).fill(GS.card))
        .overlay(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.preview.accessibilityLabel)
    }

    private func status(_ card: UpdatesCardModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if card.phase == .error {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(GS.text)
                    .accessibilityHidden(true)
            }
            Text(card.status)
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.status)
    }

    @ViewBuilder
    private func control(_ row: UpdatesCardRow, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                Text(row.title)
                    .font(GS.rowTitle)
                    .foregroundStyle(GS.text)
                Spacer(minLength: 12)
                trailing(row)
            }
            Text(row.helper)
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: height, alignment: .center)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func trailing(_ row: UpdatesCardRow) -> some View {
        switch row.control {
        case .toggle:
            Toggle(row.accessibilityLabel, isOn: Binding(
                get: { session.context.canAct && session.context.configuration.automaticChecks },
                set: { session.setAutomatic($0) }
            ))
            .toggleStyle(GSToggleStyle())
            .labelsHidden()
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityHint(row.helper)
        case .button(let title, let enabled):
            Button(title) { activate(row.id) }
                .buttonStyle(GSButtonStyle(prominent: row.id == "updates.install"))
                .disabled(!enabled)
                .accessibilityLabel(row.accessibilityLabel)
                .accessibilityHint(row.helper)
        case .text(let value):
            if row.id == UpdateConfiguration.feedURLKey {
                TextField("https://", text: Binding(
                    get: { session.context.configuration.feedURL },
                    set: { session.setFeed($0) }
                ))
                .textFieldStyle(.plain)
                .font(GS.rowText)
                .foregroundStyle(GS.text)
                .frame(maxWidth: 280)
                .accessibilityLabel(row.accessibilityLabel)
                .accessibilityHint(row.helper)
            } else {
                Text(value)
                    .font(GS.rowText)
                    .foregroundStyle(GS.text)
                    .monospacedDigit()
                    .accessibilityLabel(row.accessibilityLabel)
            }
        }
    }

    private func activate(_ id: String) {
        switch id {
        case UpdateConfiguration.checkNowKey: session.checkNow()
        case "updates.download": session.download()
        case "updates.install": session.beginInstall()
        default: break
        }
    }

    @ViewBuilder
    private var confirmation: some View {
        if case .confirm(let version) = UpdatesCard.installPrompt(state: session.state, confirming: session.confirming) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Install version \(version) and relaunch?")
                    .font(GS.rowText)
                    .foregroundStyle(GS.text)
                    .accessibilityLabel("Install version \(version) and relaunch?")
                HStack(spacing: 8) {
                    Button("Install") { session.confirmInstall() }
                        .buttonStyle(GSButtonStyle(prominent: true))
                        .accessibilityLabel("Install version \(version) and relaunch")
                    Button("Cancel") { session.cancelInstall() }
                        .buttonStyle(GSButtonStyle())
                        .accessibilityLabel("Cancel install")
                        .keyboardShortcut(.cancelAction)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.vertical, 8)
        }
    }

    private func notes(_ card: UpdatesCardModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What's new")
                .font(GS.rowTitle)
                .foregroundStyle(GS.text)
                .accessibilityAddTraits(.isHeader)
            if card.notes.isEmpty {
                Text(card.notesEmpty)
                    .font(GS.rowText)
                    .foregroundStyle(GS.secondary)
                    .accessibilityLabel(card.notesEmpty)
            } else {
                ForEach(Array(card.notes.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(GS.rowText)
                        .foregroundStyle(GS.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(line)
                }
            }
            Text("Release notes from a feed Zeus has accepted.")
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: CGFloat(card.rowHeight), alignment: .leading)
        .padding(.vertical, 8)
    }
}
