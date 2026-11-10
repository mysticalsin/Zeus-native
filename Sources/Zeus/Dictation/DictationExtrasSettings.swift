import AppKit
import SwiftUI
import ZeusCore

/// Settings › Dictation: microphone choice and test, typing instead of pasting, history window.
struct DictationExtrasSection: View {
    let settings: DictationSettings
    let topBar: TopBarModel
    let tester = MicrophoneTester.shared
    private var devices: [MicrophoneDevice] { tester.devices }

    var body: some View {
        Section("Microphone") {
            Picker("Microphone", selection: Binding(get: { settings.microphoneUID }, set: { settings.microphoneUID = $0 })) {
                Text("System default").tag(String?.none)
                ForEach(devices) { device in
                    Text(device.isDefault ? "\(device.name) (system default)" : device.name).tag(String?.some(device.uid))
                }
            }
            HStack(spacing: 10) {
                Button(tester.running ? "Stop Test" : "Test Microphone") {
                    if tester.running { tester.stop() } else { tester.start(uid: settings.microphoneUID) }
                }
                MicLevelMeter(level: tester.level)
                    .frame(height: 8)
                    .accessibilityLabel("Microphone level")
                    .accessibilityValue("\(Int(tester.level * 100)) percent")
            }
            if let message = tester.problem ?? tester.verdict ?? (tester.running ? "Say a few words…" : nil) {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .onAppear { tester.devices = Microphones.all() }
        .onDisappear { tester.stop() }

        Section("Typing") {
            Toggle("Show the text to correct before it goes in", isOn: Binding(get: { settings.previewBeforeInsert }, set: { settings.previewBeforeInsert = $0 }))
            Text("Return inserts it into the app you were in, Esc throws it away.")
                .font(.callout).foregroundStyle(.secondary)
            Toggle("Type text key by key instead of pasting", isOn: Binding(get: { settings.alwaysType }, set: { settings.alwaysType = $0 }))
            Text("Slower, but works where ⌘V is blocked. These apps are always typed into:")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(settings.typedApps, id: \.self) { bundleID in
                HStack {
                    Text(Self.appName(bundleID))
                    Spacer()
                    Button {
                        settings.typedApps.removeAll { $0 == bundleID }
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(PlainTextButtonStyle())
                    .accessibilityLabel("Stop typing into \(Self.appName(bundleID))")
                }
            }
            Menu("Add an App") {
                ForEach(Self.runningApps(excluding: settings.typedApps), id: \.bundleID) { app in
                    Button(app.name) { settings.typedApps.append(app.bundleID) }
                }
            }
            .fixedSize()
        }

        Section("History") {
            Button("Open Dictation History…") { DictationHistoryWindow.shared.show(topBar: topBar) }
            Text("Correct a dictation to teach ZEUS a word, or run it again with another mode or engine.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func runningApps(excluding: [String]) -> [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { (app.localizedName ?? $0, $0) } }
            .filter { !excluding.contains($0.1) && $0.1 != Bundle.main.bundleIdentifier }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
            .map { (name: $0.0, bundleID: $0.1) }
    }
}

private struct MicLevelMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(level > 0.95 ? Color.orange : Color.green)
                    .frame(width: proxy.size.width * level)
                    .animation(.linear(duration: 0.08), value: level)
            }
        }
    }
}
