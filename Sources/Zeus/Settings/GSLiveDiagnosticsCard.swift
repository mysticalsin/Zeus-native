import AppKit
import SwiftUI
import ZeusCore

/// Settings > Diagnostics > "Zeus right now": Zeus's own CPU, memory, heat and audio state, and a Copy button
/// for a bug report. Samples through the shared `EnergyMonitor` only while the card is on screen, so nothing
/// runs when it is closed. Snapshots show fixed values and start nothing.
struct LiveDiagnosticsCard: View {
    let context: GSContext
    var monitor = EnergyMonitor.shared
    private var audio = AudioSpectrumService.shared
    @State private var copied = false
    @State private var resetCopied: Task<Void, Never>?

    init(context: GSContext) {
        self.context = context
    }

    var body: some View {
        let live = current
        GSCard("Zeus right now") {
            ForEach(Array(live.rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { GSDivider() }
                GSRow(symbol: Self.symbol(row.field), title: row.label) { value(row) }
            }
            GSDivider()
            GSRow(symbol: "doc.on.doc", title: "Copy for a bug report",
                  text: "Zeus and macOS versions and the values above. Never a song, a file or anything you wrote. Nothing is sent anywhere.") {
                Button { copy(live) } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(GSButtonStyle())
                .accessibilityLabel(copied ? "Copied the diagnostics summary" : "Copy the diagnostics summary")
            }
        }
        .onAppear { if !TopBarStyle.isSnapshot { monitor.start() } }
        .onDisappear {
            resetCopied?.cancel()
            copied = false
            if !TopBarStyle.isSnapshot { monitor.stop() }
        }
    }

    // MARK: Values

    /// What the card shows now. Fixed in snapshots, so a captured page never depends on this Mac's load.
    private var current: LiveDiagnostics {
        let version = DiagnosticsLogModel.version, build = DiagnosticsLogModel.build
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osText = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        if TopBarStyle.isSnapshot {
            return LiveDiagnostics(cpuPercent: 0.4, memoryBytes: 96 * 1_048_576, thermal: .nominal, audio: .off,
                                   playerName: "Music", isPlaying: true, appVersion: version, build: build, osVersion: osText)
        }
        return LiveDiagnostics(
            // No CPU number until the monitor has taken its first sample, and none for a failed memory read.
            cpuPercent: monitor.hasCPUSample ? monitor.cpu : nil,
            memoryBytes: monitor.memory > 0 ? UInt64(monitor.memory * 1_048_576) : nil,
            thermal: LiveDiagnostics.thermal(from: ProcessInfo.processInfo.thermalState),
            audio: LiveDiagnostics.AudioCapture(running: audio.running, permission: audio.permission),
            nowPlaying: context.topBar?.nowPlaying,
            appVersion: version, build: build, osVersion: osText)
    }

    private func copy(_ live: LiveDiagnostics) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(live.summaryText, forType: .string)
        copied = true
        resetCopied?.cancel()
        resetCopied = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { copied = false }
        }
    }

    // MARK: Drawing

    /// A number reads as text with "High" beside it when over budget; a status reads as a symbol and a word.
    @ViewBuilder private func value(_ row: LiveDiagnostics.Row) -> some View {
        let spoken = row.isHigh ? "\(row.label) \(row.value), high" : "\(row.label) \(row.value)"
        switch row.field {
        case .cpu, .memory:
            HStack(spacing: 10) {
                if row.isHigh { badge(symbol: "exclamationmark.triangle.fill", word: "High", tone: .attention) }
                Text(row.value).font(OB.font(13.5, .semibold).monospacedDigit()).foregroundStyle(GS.text)
            }
            .accessibilityElement(children: .ignore).accessibilityLabel(spoken)
        case .heat, .audio, .nowPlaying:
            badge(symbol: Self.symbol(for: row.tone), word: row.value, tone: row.tone)
                .accessibilityElement(children: .ignore).accessibilityLabel(spoken)
        }
    }

    private func badge(symbol: String, word: String, tone: LiveDiagnostics.Tone) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13))
            Text(word).font(OB.font(13.5, .semibold))
        }
        .foregroundStyle(Self.color(tone))
    }

    private static func symbol(_ field: LiveDiagnostics.Field) -> String {
        switch field {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .heat: "thermometer.medium"
        case .audio: "waveform"
        case .nowPlaying: "music.note"
        }
    }

    private static func symbol(for tone: LiveDiagnostics.Tone) -> String {
        switch tone {
        case .ok: "checkmark.circle.fill"
        case .neutral: "minus.circle"
        case .attention: "exclamationmark.triangle.fill"
        }
    }

    private static func color(_ tone: LiveDiagnostics.Tone) -> Color {
        switch tone {
        case .ok: OB.allowed
        case .neutral: GS.secondary
        case .attention: Color(rgb: 240, 200, 130)
        }
    }
}
