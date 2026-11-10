import AppKit
import Observation
import SwiftUI
import ZeusCore

/// Superwhisper style recorder: a small floating pill at the bottom of the screen with a live
/// waveform, the mode and a timer while you speak, then a short "Transcribing" and a result mark.
/// It shows only while a dictation runs, takes no focus, and does no work while hidden.
@MainActor
final class RecorderPill {
    static let shared = RecorderPill()
    static let enabledKey = "dictation.pill"

    /// The accent of the pill. Zeus's purple lighting lives here until the shared theme tokens land.
    static let accent = Color(red: 139 / 255, green: 92 / 255, blue: 246 / 255)

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static let voiceGlowEnabledKey = VoiceGlowSettings.enabledKey
    static let voiceGlowVariantKey = VoiceGlowSettings.variantKey

    static var voiceGlowEnabled: Bool {
        get { VoiceGlowSettings.shared.enabled }
        set { VoiceGlowSettings.shared.enabled = newValue }
    }

    static var voiceGlowVariant: VoiceGlowVariant {
        get { VoiceGlowSettings.shared.variant }
        set { VoiceGlowSettings.shared.variant = newValue }
    }

    private var panel: NSPanel?
    private weak var topBar: TopBarModel?
    private var hideTask: Task<Void, Never>?
    private var tracking = false

    static func markStarted(_ date: Date) { RecorderPillView.startedAt = date }

    func attach(_ topBar: TopBarModel) {
        self.topBar = topBar
        guard !tracking else { return }
        tracking = true
        observe()
    }

    private func observe() {
        guard let topBar else { return }
        withObservationTracking {
            _ = topBar.dictationPhase
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.phaseChanged()
                self?.observe()
            }
        }
    }

    private func phaseChanged() {
        guard let topBar, Self.isEnabled else { hide(); return }
        switch topBar.dictationPhase {
        case .idle: hide()
        case .listening, .transcribing, .rewriting:
            hideTask?.cancel()
            show(topBar)
        case .done, .failed:
            hideTask?.cancel()
            show(topBar)
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1_100))
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    private func show(_ topBar: TopBarModel) {
        let panel = self.panel ?? makePanel(topBar)
        self.panel = panel
        placePanel(panel)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup({ $0.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
                panel.animator().alphaValue = 1 }, completionHandler: nil)
        }
    }

    private func placePanel(_ panel: NSPanel) {
        hideTask?.cancel()
        if CursorPresenceController.isEnabled {
            CursorPresenceController.shared.track(panel, size: { RecorderPillView.size }, caretRect: { CaretLocator.currentCaretRect() })
        } else {
            CursorPresenceController.shared.stop()
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            let size = RecorderPillView.size
            let frame = CGRect(x: visible.midX - size.width / 2, y: visible.minY + 28, width: size.width, height: size.height)
            panel.setFrame(frame, display: true)
        }
    }

    private func hide() {
        hideTask?.cancel()
        guard let panel, panel.isVisible else { return }
        if let topBar, !CursorPresenceGuard.delayedPillHideShouldStopPresence(isActiveDictation: topBar.isDictating) {
            return
        }
        CursorPresenceController.shared.stop()
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.14; panel.animator().alphaValue = 0 }) { [weak panel] in
            MainActor.assumeIsolated { panel?.orderOut(nil) }
        }
    }

    private func makePanel(_ topBar: TopBarModel) -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: RecorderPillView.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let hosting = NSHostingView(rootView: RecorderPillView(topBar: topBar))
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }
}

struct RecorderPillView: View {
    static let size = CGSize(width: 292, height: 48)
    let topBar: TopBarModel

    var body: some View {
        let glow = VoiceGlowSettings.shared
        let enabled = glow.enabled
        let variant = glow.variant
        HStack(spacing: 12) {
            leading
            content
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(width: Self.size.width, height: Self.size.height)
        // Capsule fill, then the glow over it (rounded clip), all beneath the pill's content.
        .background {
            Capsule(style: .continuous).fill(Color(white: 0.09, opacity: 0.96))
                .voiceGlow(level: { topBar.dictationLevel },
                           processing: topBar.dictationPhase == .transcribing || topBar.dictationPhase == .rewriting,
                           preset: .pill, variant: variant,
                           strength: !enabled ? 0 : (topBar.isDictating ? 1 : 0.4),
                           cornerRadius: Self.size.height / 2,
                           active: enabled && topBar.dictationPhase != .idle,
                           layer: .over,
                           driver: .pill)
        }
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictation recorder")
    }

    @ViewBuilder private var leading: some View {
        switch topBar.dictationPhase {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green).font(.system(size: 18))
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.orange).font(.system(size: 18))
        case .transcribing, .rewriting:
            ThinkingOrbView(mode: .working).frame(width: 18, height: 18)
                .accessibilityLabel("Transcribing")
        case .listening:
            ThinkingOrbView(mode: .listening(level: min(1, topBar.dictationLevel * 1.6))).frame(width: 18, height: 18)
                .accessibilityLabel("Listening")
        case .idle: EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch topBar.dictationPhase {
        case .listening:
            VStack(alignment: .leading, spacing: 1) {
                PillWave(levels: topBar.dictationLevels).frame(width: 120, height: 22)
            }
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                Text(Self.clock(context.date.timeIntervalSince(started))).font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 34, alignment: .trailing)
            }
        case .transcribing: label("Transcribing")
        case .rewriting: label("Writing with \(topBar.dictationModeName)")
        case .done: label("Written")
        case .failed(let message): label(message)
        case .idle: EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        if topBar.dictationPhase == .listening {
            HStack(spacing: 8) {
                pillButton("xmark", "Cancel dictation") { DictationHub.shared.controller?.cancel() }
                pillButton("checkmark", "Finish dictation", filled: true) { DictationHub.shared.controller?.finish() }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
    }

    private func pillButton(_ symbol: String, _ name: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                .foregroundStyle(filled ? Color.white : Color.white.opacity(0.75))
                .frame(width: 26, height: 26)
                .background(Circle().fill(filled ? RecorderPill.accent : Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }

    private var started: Date { Self.startedAt }
    nonisolated(unsafe) static var startedAt = Date()

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Bars drawn from the model's own level history; redraws only when a new level arrives.
private struct PillWave: View {
    let levels: [Double]
    var body: some View {
        Canvas { context, size in
            let count = levels.count
            guard count > 0 else { return }
            let gap: CGFloat = 2
            let width = max(1.5, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            for (index, level) in levels.enumerated() {
                let height = max(3, CGFloat(min(1, level * 1.6)) * size.height)
                let rect = CGRect(x: CGFloat(index) * (width + gap), y: (size.height - height) / 2, width: width, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(RecorderPill.accent.opacity(0.45 + 0.55 * min(1, level * 1.6))))
            }
        }
        .accessibilityHidden(true)
    }
}
