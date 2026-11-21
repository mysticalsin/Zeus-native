import SwiftUI
import ZeusCore

extension PortalSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(PortalSettingsSection()) }
}

struct PortalSettingsSection: View {
    private var store: SettingsStore { .shared }
    @State private var flow = PortalDropFlow()
    @State private var removal = PortalRemovalFlow()
    @State private var targeted = false

    var body: some View {
        let board = PortalDeviceBoardBuilder.make(reading)
        let motion = Motion.reduced
        let preview = PortalSectionModel.preview(flow.phase, reduceMotion: motion)
        let controls = PortalSectionModel.controls(for: board, flow: flow)
        ScrollView {
            VStack(alignment: .leading, spacing: CGFloat(GlassSettingsMetrics.cardSpacing)) {
                previewTile(preview)
                    .focusable(true)
                card("File tray", controls.filter { ["portal.preview", "portal.conversion", "portal.reset"].contains($0.id) })
                card("Nearby devices", controls.filter { !$0.id.hasPrefix("portal.preview") && $0.id != "portal.conversion" && $0.id != "portal.reset" })
            }
            .padding(CGFloat(GlassSettingsMetrics.panelPadding))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private var reading: PortalFlingReading {
        let fling = FlingService.current
        let paired = (fling?.pairedMacs ?? []).map {
            PortalPairedDevice(id: $0.id, name: $0.name, lastSeen: $0.lastSeen)
        }
        return PortalFlingReading(
            enabled: store.string("fling.enabled"),
            receiveInBackground: store.string("fling.receiveInBackground"),
            deviceName: store.string("fling.deviceName"),
            visibility: store.string("fling.visibility"),
            autoAcceptPaired: store.string("fling.autoAcceptPaired"),
            saveMode: store.string("fling.saveMode"),
            papers: store.string("fling.papers"),
            flickSensitivity: store.string("fling.flickSensitivity"),
            openLinks: store.string("fling.openLinks"),
            localNetworkDenied: fling?.localNetworkDenied ?? false,
            peersKnown: fling != nil,
            notchOpen: true,
            paired: paired,
            removal: removal.phase
        )
    }

    private func previewTile(_ preview: PortalPreviewTile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(preview.title).font(GS.cardTitle).foregroundStyle(GS.text)
            Text(preview.detail).font(GS.rowText).foregroundStyle(GS.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: CGFloat(GlassSettingsMetrics.controlRow), alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).fill(GS.card))
        .overlay(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).strokeBorder(targeted ? GS.selectedText : GS.cardStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(preview.title). \(preview.detail)")
        .animation(preview.animationDuration == 0 ? nil : .easeOut(duration: preview.animationDuration), value: preview.phase)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            let current = flow
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { flow = PortalDropActions.convert(url: url, current: current) }
                    }
                }
            }
            return !providers.isEmpty
        }
    }

    private func card(_ title: String, _ controls: [PortalControl]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(GS.cardTitle).foregroundStyle(GS.text)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            ForEach(controls) { control in
                row(control)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).fill(GS.card))
        .overlay(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
    }

    private func row(_ control: PortalControl) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(control.label).font(GS.rowTitle).foregroundStyle(GS.text)
                Text(control.helper).font(GS.rowText).foregroundStyle(GS.secondary)
                    .frame(minHeight: CGFloat(GlassSettingsMetrics.helperLine), alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing(control)
        }
        .frame(minHeight: CGFloat(GlassSettingsMetrics.controlRow), alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(control.label)
        .focusable(true)
    }

    @ViewBuilder
    private func trailing(_ control: PortalControl) -> some View {
        switch control.id {
        case "portal.sync":
            Toggle(control.label, isOn: store.boolBinding("fling.enabled"))
                .toggleStyle(GSToggleStyle())
                .labelsHidden()
                .accessibilityLabel(control.label)
        case "portal.visibility":
            GSPopup(selection: store.stringBinding("fling.visibility"),
                    options: SettingsCatalog.option("fling.visibility")?.choices ?? ["Everyone nearby", "Paired only", "Off"],
                    label: control.label)
        case "portal.deviceName":
            GSTextInput(text: store.stringBinding("fling.deviceName"), placeholder: "This Mac's name", label: control.label)
        case "portal.reset":
            Button(control.label) { _ = flow.reset() }
                .buttonStyle(GSButtonStyle())
                .accessibilityLabel(control.label)
        case "portal.confirmRemove":
            Button(control.label) { confirmRemoval() }
                .buttonStyle(GSButtonStyle())
                .accessibilityLabel(control.label)
        case "portal.cancelRemove":
            Button(control.label) { _ = removal.dismiss() }
                .buttonStyle(GSButtonStyle())
                .accessibilityLabel(control.label)
        default:
            if control.id.hasPrefix("portal.remove.") {
                Button(control.label) { askRemoval(String(control.id.dropFirst("portal.remove.".count))) }
                    .buttonStyle(GSButtonStyle())
                    .accessibilityLabel(control.label)
            }
        }
    }

    private func askRemoval(_ id: String) {
        let known = Set((FlingService.current?.pairedMacs ?? []).map(\.id))
        _ = removal.ask(id: id, known: known)
    }

    private func confirmRemoval() {
        guard case .confirming(let id) = removal.phase else { return }
        _ = removal.confirm()
        _ = FlingService.current?.removePairedMac(id: id)
    }
}
