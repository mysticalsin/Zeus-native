import SwiftUI
import ZeusCore

extension FocusSectionSlot: GlassSlotPage {
    static func erasePage() -> AnyView { AnyView(FocusSettingsSection()) }
}

/// The Focus page. Spacing comes from the section model. The shell has no metrics token yet.
struct FocusSettingsSection: View {
    @State private var session = FocusSectionSession(defaults: .standard)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let content = session.content()
        ScrollView {
            VStack(alignment: .leading, spacing: content.cardGap) {
                Text(content.title)
                    .font(GS.pageTitle)
                    .foregroundStyle(GS.text)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(content.title)
                preview(content)
                status(content)
                controls(content)
                rules(content)
            }
            .padding(content.panelPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            session = FocusSectionSession(defaults: .standard)
            _ = session.handle(.reduceMotion(reduceMotion))
        }
        .onChange(of: reduceMotion) { _, value in
            _ = session.handle(.reduceMotion(value))
        }
    }

    private func preview(_ content: FocusSectionContent) -> some View {
        let home = session.home()
        return VStack(alignment: .leading, spacing: 8) {
            Text(content.preview.title)
                .font(GS.cardTitle)
                .foregroundStyle(GS.text)
                .accessibilityAddTraits(.isHeader)
            Text(content.preview.line)
                .font(GS.rowTitle)
                .foregroundStyle(GS.text)
                .animation(content.preview.animates ? .easeOut(duration: content.preview.animationDuration) : nil, value: content.preview.line)
            Text("\(home.title), \(home.subtitle). \(home.nameStatus)")
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
            Text(lockLine)
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
        }
        .padding(GS.cardInset)
        .frame(maxWidth: .infinity, minHeight: content.rowHeight, alignment: .leading)
        .background(card)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(content.preview.accessibilityLabel)
    }

    private func status(_ content: FocusSectionContent) -> some View {
        let (title, text, symbol) = statusCopy(content.status)
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(GS.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(GS.rowTitle).foregroundStyle(GS.text)
                Text(text).font(GS.rowText).foregroundStyle(GS.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if case .showing = session.transition.state {
                Button("Dismiss") { _ = session.handle(.dismissOverlay) }
                    .buttonStyle(GSButtonStyle())
                    .accessibilityLabel("Dismiss overlay")
            }
        }
        .padding(.horizontal, GS.cardInset)
        .frame(minHeight: content.rowHeight)
        .background(card)
        .accessibilityElement(children: .contain)
    }

    private func controls(_ content: FocusSectionContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(content.controls) { control in
                row(control, height: content.rowHeight)
                if control.id != content.controls.last?.id {
                    Rectangle().fill(GS.separator).frame(height: 1).accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, GS.cardInset)
        .background(card)
    }

    private func rules(_ content: FocusSectionContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Overlays during a Focus")
                .font(GS.cardTitle)
                .foregroundStyle(GS.text)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)
            Text(content.filterSummary)
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
                .padding(.bottom, 8)
            ForEach(FocusOverlayFilter.table, id: \.kind) { rule in
                let decision = session.overlayDecision(rule.kind)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ruleTitle(rule.kind)).font(GS.rowTitle).foregroundStyle(GS.text)
                        Text(ruleHelper(rule)).font(GS.rowText).foregroundStyle(GS.secondary)
                    }
                    Spacer(minLength: 12)
                    Text(decisionTitle(decision))
                        .font(GS.rowText)
                        .foregroundStyle(GS.secondary)
                }
                .frame(minHeight: content.rowHeight, alignment: .center)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(ruleTitle(rule.kind)), \(decisionTitle(decision)). \(ruleHelper(rule))")
            }
        }
        .padding(.horizontal, GS.cardInset)
        .padding(.bottom, 8)
        .background(card)
    }

    @ViewBuilder
    private func row(_ control: FocusControlSpec, height: Double) -> some View {
        if control.id == FocusSettingKey.homeWidget {
            VStack(alignment: .leading, spacing: 4) {
                Text(control.title).font(GS.rowTitle).foregroundStyle(GS.text)
                Text(control.helper).font(GS.rowText).foregroundStyle(GS.secondary)
                Text(control.accessibilityValue).font(GS.rowText).foregroundStyle(GS.text)
            }
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(control.accessibilityLabel)
        } else {
            Toggle(isOn: binding(control.id, isOn: control.isOn)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(control.title).font(GS.rowTitle).foregroundStyle(GS.text)
                    Text(control.helper).font(GS.rowText).foregroundStyle(GS.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .frame(minHeight: height)
            .accessibilityLabel(control.accessibilityLabel)
            .accessibilityValue(control.accessibilityValue)
        }
    }

    private func binding(_ id: String, isOn: Bool) -> Binding<Bool> {
        Binding(
            get: { isOn },
            set: { on in
                switch id {
                case FocusSettingKey.transitionOverlay: _ = session.handle(.setTransition(on))
                case FocusSettingKey.overlaysAllowed: _ = session.handle(.setOverlaysAllowed(on))
                case FocusSettingKey.lockScreen: _ = session.handle(.setLockScreen(on))
                case FocusSettingKey.readName: _ = session.handle(.setReadName(on))
                case FocusSettingKey.storeFile: _ = session.handle(.setStoreFile(on))
                case FocusSettingKey.localNetwork: _ = session.handle(.setLocalNetwork(on))
                case FocusSettingKey.sharedLink: _ = session.handle(.setSharedLink(on))
                default: break
                }
                SettingsStore.shared.set(id, on ? "true" : "false")
            }
        )
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous)
            .fill(GS.card)
            .overlay(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
    }

    private var lockLine: String {
        switch session.lockScreen() {
        case .hidden: "Lock screen hidden"
        case .empty: "No Focus is on"
        case .loading: "Checking the lock screen"
        case .showing(let label): "Lock screen: \(label)"
        case .unavailable(let text): "Lock screen: \(text)"
        }
    }

    private func statusCopy(_ status: FocusSectionStatus) -> (String, String, String) {
        switch status {
        case .loading:
            return ("Checking", "Waiting for permission before anything is read.", "clock")
        case .empty:
            return ("Nothing here", "Home slot 2 is showing another widget.", "rectangle.dashed")
        case .unavailable(let text):
            return (text, "The rest of Focus stays usable.", "exclamationmark.circle")
        case .ready:
            return ("Ready", "The home timer stays available.", "checkmark.circle")
        }
    }

    private func ruleTitle(_ kind: FocusOverlayKind) -> String {
        switch kind {
        case .transition: "Transition overlay"
        case .timer: "Timer"
        case .media: "Media"
        case .notification: "Notifications"
        case .screenEdge: "Screen edge"
        case .pointingTrail: "Pointer trail"
        case .notchCue: "Notch cue"
        }
    }

    private func ruleHelper(_ rule: FocusOverlayRule) -> String {
        if rule.showsName { return "May show a name only after reading is allowed." }
        return rule.allowed ? "Can appear while a Focus is on." : "Stays hidden while a Focus is on."
    }

    private func decisionTitle(_ decision: FocusOverlayDecision) -> String {
        switch decision {
        case .unfiltered: "Not in a Focus"
        case .allowed: "Allowed"
        case .blocked: "Blocked"
        case .unavailable: "Unavailable"
        }
    }
}
