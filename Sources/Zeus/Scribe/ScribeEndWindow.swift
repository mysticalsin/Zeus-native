import AppKit
import SwiftUI
import ZeusCore

/// One native card follows the real end workflow. It never advances a session or simulates completion.
/// Production controllers present it; inert automated controllers never construct an NSPanel.
@MainActor
final class ScribeEndWindow {
    static let shared = ScribeEndWindow()
    private var panel: NSPanel?

    func present(scribe: ScribeController) {
        if let panel { panel.orderFrontRegardless(); return }
        let panel = EndPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 240),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.contentView = NSHostingView(rootView: ScribeEndWindowView(scribe: scribe))
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setAccessibilityLabel("Meeting ending and notes")
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 396, y: screen.visibleFrame.maxY - 256))
        }
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private final class EndPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
}

private struct ScribeEndWindowView: View {
    let scribe: ScribeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Meetings", systemImage: "waveform.and.mic")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { ScribeEndWindow.shared.hide() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide meeting window")
                    .accessibilityHint("The current recording or save operation continues.")
            }
            content
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 380, height: 240, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: scribe.phase)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var content: some View {
        switch scribe.phase {
        case .ending:
            Text(scribe.endStopRequested ? "Finishing recording…" : "Meeting ending in \(scribe.endingRemaining ?? 9)s")
                .font(.system(size: 20, weight: .semibold)).monospacedDigit()
                .accessibilityAddTraits(.isHeader)
            Text(scribe.endingReason == .boundCallAppClosed
                 ? "The call app closed. You can keep recording this meeting."
                 : "You asked to stop. Your notes will be saved after recording ends.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Button("End meeting now") { scribe.confirmEnd() }.buttonStyle(.borderedProminent)
                Button("Keep recording") { scribe.keepRecording() }.buttonStyle(.bordered)
            }
            .disabled(scribe.endStopRequested)
        case .processing:
            if let issue = scribe.completionSaveIssue, let id = scribe.phase.sessionID {
                Label("Notes couldn't be saved", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 17, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text(issue).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(4)
                Button("Retry save") { scribe.retrySave(id) }.buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Finishing your notes…").font(.system(size: 18, weight: .semibold))
                }
                Text("Recording has ended. This window will show the note after it is saved.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .complete(let id):
            Label("Meeting saved", systemImage: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold)).accessibilityAddTraits(.isHeader)
            if let recap = scribe.recaps.first(where: { $0.id == id }) {
                Text(recap.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(recap.notes.summary.isEmpty ? "Your transcript and notes are ready." : recap.notes.summary)
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
            }
            Button("Open notes") {
                guard let panel = NotchControllerBridge.controller, let topBar = panel.topBar,
                      scribe.openRecap(id) else { return }
                ScribeEndWindow.shared.hide()
                topBar.selectedTab = .scribe
                panel.show(.panel)
            }
            .buttonStyle(.borderedProminent)
        default:
            Text("Meeting recording").font(.system(size: 18, weight: .semibold))
        }
    }
}
