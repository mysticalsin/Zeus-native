import SwiftUI

/// First-run Permissions step: every access ZEUS can use, why, and an Allow button that asks
/// macOS only when pressed. Status updates live (the setup window refreshes every second).
/// This and Settings › Permissions are the only places ZEUS asks.
struct PermissionsStep: View {
    let permissions: PermissionsModel

    static func reason(_ kind: PermissionsModel.Kind) -> (symbol: String, title: String, why: String) {
        switch kind {
        case .microphone: ("mic", "Microphone", "Hears you while you hold the talk key or dictate.")
        case .speech: ("waveform", "Speech Recognition", "Turns your voice into text on this Mac.")
        case .accessibility: ("accessibility", "Accessibility", "Notices the talk key, inserts dictated text and clicks where you agree.")
        case .camera: ("camera", "Camera", "Records you while you read in the teleprompter.")
        case .screen: ("rectangle.dashed", "Screen Recording", "Lets Zeus see what you point at when you ask.")
        case .calendar: ("calendar", "Calendar", "Shows your next events in the notch.")
        case .reminders: ("checklist", "Reminders", "Shows what is due today.")
        case .automation: ("gearshape.2", "Automation", "Reads speaker notes from Keynote or PowerPoint and controls Music.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Allow what you need").font(.title.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text("Each one is optional. Zeus asks only when you press Allow, and you can change any of them later in Settings.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                ForEach(PermissionsModel.Kind.allCases) { kind in row(kind) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ kind: PermissionsModel.Kind) -> some View {
        let info = Self.reason(kind)
        let granted = permissions.granted[kind] == true
        return HStack(spacing: 10) {
            Image(systemName: info.symbol).frame(width: 20).foregroundStyle(Theme.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.title).fontWeight(.medium)
                Text(info.why).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon).foregroundStyle(.green).font(.callout)
            } else {
                Button("Allow") { permissions.request(kind) }
                    .accessibilityHint("Asks macOS for \(info.title) access. \(info.why)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(info.title), \(granted ? "allowed" : "not allowed")")
    }
}
