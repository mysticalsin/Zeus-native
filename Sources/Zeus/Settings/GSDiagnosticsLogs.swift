import AppKit
import SwiftUI
import ZeusCore

/// Settings > Diagnostics > Logs: the flight recorder (the last ~2,000 app events) and "Export diagnostics".
@MainActor
final class DiagnosticsLogModel: ObservableObject {
    static let filters = ["All", "Voice", "Agents", "Cues", "Sounds", "Errors"]
    @Published var filter = "All"
    @Published var message: String?
    @Published var exported: URL?

    static func sources(for filter: String) -> Set<String>? {
        switch filter {
        case "Voice": ["voice"]
        case "Agents": ["agent"]
        case "Cues": ["cue"]
        case "Sounds": ["sound"]
        case "Errors": ["error"]
        default: nil
        }
    }

    /// Newest last, at most `limit` rows after the filter.
    func rows(limit: Int = 60) -> [RecordedEvent] {
        let all = FlightRecorder.shared.events
        let filtered = Self.sources(for: filter).map { keep in all.filter { keep.contains($0.source) } } ?? all
        return Array(filtered.suffix(limit))
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ZeusCoreVersion.string }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev" }

    func export(to folder: URL) {
        let settings = (try? SettingsStore.shared.exportJSON()) ?? Data("{}".utf8)
        let logs = [VoiceLog.url, VoiceLog.url.deletingPathExtension().appendingPathExtension("old.log")]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let input = DiagnosticsExporter.Input(version: Self.version, build: Self.build, settingsJSON: settings, logFiles: logs)
        message = "Exporting\u{2026}"
        // The zip is built by `ditto`: wait for it on a background thread so the window stays live.
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { Result { try DiagnosticsExporter.export(input, to: folder) } }.value
            guard let self else { return }
            switch result {
            case .success(let zip):
                exported = zip
                message = "Saved \(zip.lastPathComponent) to \(folder.lastPathComponent)."
            case .failure(let error):
                exported = nil
                message = "Could not export: \(error.localizedDescription)"
            }
        }
    }

    func exportToDesktop() {
        export(to: FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0])
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export here"
        panel.message = "Choose where to save the diagnostics zip."
        if panel.runModal() == .OK, let url = panel.url { export(to: url) }
    }

    func copyVisible() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rows(limit: 2000).map(FlightRecorder.line).joined(separator: "\n"), forType: .string)
        message = "Copied the log."
    }
}

struct DiagnosticsLogsCard: View {
    @StateObject private var model = DiagnosticsLogModel()

    var body: some View {
        GSCard("Logs") {
            GSRow(symbol: "line.3.horizontal.decrease", title: "Show") {
                GSPopup(selection: Binding(get: { model.filter }, set: { model.filter = $0 }), options: DiagnosticsLogModel.filters)
            }
            TickingView(interval: 2, paused: TopBarStyle.isSnapshot) { _ in
                ScrollView {
                    logList(model.rows())
                }
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 180, alignment: .topLeading)
                .clipped()
            }
            .padding(.top, 8)
            GSDivider()
            GSRow(symbol: "square.and.arrow.up", title: "Export diagnostics", text: "") {
                HStack(spacing: 8) {
                    Button("Copy log") { model.copyVisible() }.buttonStyle(GSButtonStyle())
                    Button("Choose folder") { model.chooseFolder() }.buttonStyle(GSButtonStyle())
                    Button("Export") { model.exportToDesktop() }.buttonStyle(GSButtonStyle(prominent: true))
                }
            }
            if let message = model.message {
                HStack(spacing: 10) {
                    Text(message).font(GS.rowText).foregroundStyle(GS.secondary)
                    if let zip = model.exported {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([zip]) }.buttonStyle(GSButtonStyle())
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func logList(_ rows: [RecordedEvent]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if rows.isEmpty {
                GSEmptyState(symbol: "text.append", title: "No log entries yet",
                             text: "Voice, agent and sound events show here as they happen. Nothing is recorded while you are idle.")
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, event in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Self.time.string(from: event.date)).foregroundStyle(GS.secondary)
                    Text(event.source).foregroundStyle(color(event.source)).frame(width: 46, alignment: .leading)
                    Text(event.stage).foregroundStyle(GS.text).frame(width: 84, alignment: .leading).lineLimit(1)
                    Text(event.detail).foregroundStyle(GS.secondary).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11, design: .monospaced))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.35)))
        .accessibilityLabel("Recent app events")
    }

    private func color(_ source: String) -> Color {
        switch source {
        case "error": Color(rgb: 255, 120, 120)
        case "agent": Color(rgb: 140, 180, 255)
        case "cue": Color(rgb: 200, 160, 255)
        case "sound": Color(rgb: 150, 220, 170)
        default: Color(rgb: 240, 200, 130)
        }
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
