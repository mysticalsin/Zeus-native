import SwiftUI
import ZeusCore

/// Scribe's tab. The stage (idle, recording, writing, notes ...) changes only on session-machine events;
/// The view clock only draws the beam, transcript reveal and wash; it never advances a recording.
struct ScribePage: View {
    let topBar: TopBarModel
    let scribe: ScribeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScribeOpenScope { pageBody }
    }

    private var pageBody: some View {
        VStack(spacing: 6) {
            // Persistent until the person retries or dismisses it; the controller also announces it.
            // At most one storage banner is shown, the most urgent first; the rest are counted, and each
            // appears as the one above it is dismissed or resolved, so the fixed page never overflows.
            let banners = storageBanners
            if let first = banners.first {
                first
                if banners.count > 1 {
                    Text("\(banners.count - 1) more notice\(banners.count == 2 ? "" : "s") after this one")
                        .font(TopBarStyle.label(9)).foregroundStyle(Theme.cloudQuiet)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(spacing: 8) {
                Tile(padding: 0) {
                    ZStack(alignment: .topLeading) {
                        ScribeCardBeam(scribe: scribe,
                            reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
                        ScribeStage(topBar: topBar, scribe: scribe,
                            reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
                            .padding(CardFinish.inset)
                            .scribeEntrance(.panel)
                    }
                }
            }
        }
    }

}

extension ScribePage {
    /// Every notice that is waiting, most urgent first: a meeting that isn't saved (its text exists only in
    /// memory), then the load, cleanup, checkpoint and delete warnings.
    fileprivate var storageBanners: [AnyView] {
        let scribe = self.scribe
        var banners: [AnyView] = []
        // It stays (in memory) until it is saved or the person confirms discarding it; there is no plain Dismiss.
        for meeting in scribe.unsavedMeetings {
            banners.append(AnyView(ScribeUnsavedBanner(scribe: scribe, meeting: meeting)))
        }
        if let issue = scribe.loadIssue {
            banners.append(AnyView(ScribeIssueBanner(text: issue, actionTitle: nil, action: {}, dismiss: { scribe.dismissLoadIssue() })))
        }
        if let issue = scribe.cleanupIssue {
            banners.append(AnyView(ScribeIssueBanner(
                text: issue, actionTitle: "Try again", action: { scribe.retryCleanup() }, dismiss: { scribe.dismissCleanupIssue() })))
        }
        if let issue = scribe.checkpointIssue {
            banners.append(AnyView(ScribeIssueBanner(text: issue, actionTitle: nil, action: {}, dismiss: { scribe.dismissCheckpointIssue() })))
        }
        if let issue = scribe.deleteIssue {
            banners.append(AnyView(ScribeIssueBanner(text: issue, actionTitle: nil, action: {}, dismiss: { scribe.dismissDeleteIssue() })))
        }
        return banners
    }
}

/// A warning that stays on the page: a readable sentence for VoiceOver plus a recovery action and Dismiss.
private struct ScribeIssueBanner: View {
    let text: String
    var actionTitle: String?
    let action: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.ember)
                .accessibilityHidden(true)
            Text(text)
                .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Warning: \(text)")
            Spacer(minLength: 0)
            if let actionTitle {
                NotchActionButton(title: actionTitle, tint: TopBarStyle.rec) { action() }
            }
            NotchActionButton(title: "Dismiss", tint: Theme.cloudSecondary, filled: false) { dismiss() }
                .accessibilityHint("Hides this warning.")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
        .accessibilityElement(children: .contain)
    }
}

/// A meeting whose file couldn't be written. Retry, or discard it after an explicit confirmation.
private struct ScribeUnsavedBanner: View {
    let scribe: ScribeController
    let meeting: ScribeUnsavedMeeting

    var body: some View {
        let confirming = scribe.pendingDiscardID == meeting.id
        let text = confirming
            ? "Discard “\(meeting.title)”? It isn't saved anywhere, so it can't be recovered."
            : meeting.message
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.ember)
                .accessibilityHidden(true)
            Text(text)
                .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Warning: \(text)")
            Spacer(minLength: 0)
            if confirming {
                NotchActionButton(title: "Keep meeting", tint: TopBarStyle.rec) { scribe.keepUnsaved() }
                NotchActionButton(title: "Discard meeting", tint: Theme.cloudSecondary, filled: false) {
                    scribe.discardUnsaved(meeting.id)
                }
                .accessibilityHint("Permanently throws away this unsaved meeting.")
            } else {
                NotchActionButton(title: "Retry save", tint: TopBarStyle.rec) { scribe.retrySave(meeting.id) }
                NotchActionButton(title: "Discard meeting", tint: Theme.cloudSecondary, filled: false) {
                    scribe.requestDiscardUnsaved(meeting.id)
                }
                .accessibilityHint("Asks before throwing away this unsaved meeting. It can't be recovered.")
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
        .accessibilityElement(children: .contain)
    }
}

/// A transcription problem of the current meeting, without actions (it clears when the meeting is closed).
struct ScribeIssueLine: View {
    let text: String
    /// Keeps a warning compact where the page needs the room (the live transcript).
    var lineLimit: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.ember)
                .accessibilityHidden(true)
            Text(text)
                .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudPrimary)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: \(text)")
    }
}

func scribeColor(_ rgb: ScribeGlow.RGB) -> Color {
    Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
}

private struct ScribeStage: View {
    let topBar: TopBarModel
    let scribe: ScribeController
    let reduceMotion: Bool
    let reduceTransparency: Bool

    var body: some View {
        Group {
            if case .complete = scribe.phase {
                ScribeCompletedStage(scribe: scribe, reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
            } else {
                content(scribe.presentation(at: Date(), reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func content(_ state: ScribePresentation) -> some View {
        switch state {
        case .idle:
            if scribe.openedRecap != nil {
                ScribeRecapDetail(scribe: scribe)
            } else {
                ScribeIdle(scribe: scribe)
            }
        case .connecting:
            ScribeConnecting(scribe: scribe, state: state)
        case .recording:
            ScribeRecording(scribe: scribe, state: state, reduceMotion: reduceMotion)
        case .confirmingEnd:
            ScribeConfirmEnd(topBar: topBar, scribe: scribe, state: state)
        case .writing:
            ScribeWriting(scribe: scribe, state: state)
        case .revealing:
            ScribeNotesView(scribe: scribe)
        case .complete:
            ScribeNotesView(scribe: scribe)
        case .failed(let reason):
            ScribeFailed(scribe: scribe, reason: reason, state: state)
        }
    }
}

/// A finite clock for the existing completion wash only. Settled notes never share the beam's clock.
private struct ScribeCompletedStage: View {
    let scribe: ScribeController
    let reduceMotion: Bool
    let reduceTransparency: Bool

    var body: some View {
        if reduceMotion || scribe.revealStart == nil {
            // Reduced Motion pauses display links: completed content must be immediately readable.
            ScribeNotesView(scribe: scribe)
        } else {
            DisplaySynchronizedView(preferredFramesPerSecond: 240,
                until: scribe.revealStart?.addingTimeInterval(ScribeGlow.revealDuration(reduceMotion: false))) { context in
                let elapsed = scribe.revealElapsed(at: context.date)
                ZStack(alignment: .bottom) {
                    ScribeNotesView(scribe: scribe)
                        .opacity(ScribeGlow.contentOpacity(t: elapsed, reduceMotion: false))
                    if !reduceTransparency {
                        ScribeGlowLayer(stage: .reveal, t: elapsed, reduceMotion: false)
                    }
                }
            }
        }
    }
}

/// A view-local drawing origin survives recording → countdown → writing → completion.
/// The meter is the existing capture-side envelope, not a second audio analyser.
private struct ScribeCardBeam: View {
    let scribe: ScribeController
    let reduceMotion: Bool
    let reduceTransparency: Bool
    @State private var session: ScribeSessionID?
    @State private var origin: Date?
    @State private var processingOrigin: Date?

    private var visible: Bool {
        if scribe.isRecording { return true }
        switch scribe.phase {
        case .processing: return true
        case .complete: return scribe.completedNoticeID != nil
        default: return false
        }
    }

    private var processing: Bool {
        switch scribe.phase {
        case .processing, .complete: return true
        default: return false
        }
    }

    private func opacity(at date: Date) -> Double {
        guard case .complete = scribe.phase else { return 1 }
        if reduceMotion || reduceTransparency { return 1 }
        return ScribeGlow.glowOpacity(stage: .reveal, t: scribe.revealElapsed(at: date), reduceMotion: false)
    }

    var body: some View {
        DisplaySynchronizedView(paused: !visible || reduceMotion || reduceTransparency,
            preferredFramesPerSecond: 240, until: completionDeadline) { context in
            if visible {
                AssistantBeamView(frame: AssistantBeam.frame(
                    elapsed: max(0, context.date.timeIntervalSince(origin ?? scribe.stageStart)),
                    level: scribe.isRecording ? (scribe.levelHistory.last ?? 0) : 0,
                    processing: processing,
                    processingElapsed: max(0, context.date.timeIntervalSince(processingOrigin ?? scribe.stageStart)),
                    reduceMotion: reduceMotion || reduceTransparency),
                    reduceTransparency: reduceTransparency, cornerRadius: CardFinish.radius)
                    .opacity(opacity(at: context.date))
            }
        }
        .onChange(of: scribe.phase, initial: true) { _, phase in
            guard let next = phase.sessionID else { session = nil; origin = nil; processingOrigin = nil; return }
            if session != next || origin == nil {
                session = next
                origin = scribe.stageStart
                processingOrigin = nil
            }
            if case .processing = phase, processingOrigin == nil { processingOrigin = scribe.stageStart }
            if case .failed = phase { origin = nil; processingOrigin = nil }
        }
    }

    private var completionDeadline: Date? {
        guard case .complete = scribe.phase else { return nil }
        return scribe.revealStart?.addingTimeInterval(ScribeGlow.revealDuration(reduceMotion: false))
    }
}

// MARK: Glow

/// A purple band rising from the bottom edge. Height, opacity and timing all come from `ScribeGlow`.
private struct ScribeGlowLayer: View {
    let stage: ScribeGlow.Stage
    let t: TimeInterval
    let reduceMotion: Bool

    var body: some View {
        let height = ScribeGlow.glowHeight(stage: stage, t: t, reduceMotion: reduceMotion)
        let opacity = ScribeGlow.glowOpacity(stage: stage, t: t, reduceMotion: reduceMotion)
        let edge = stage == .writing ? 0.35 + 0.65 * ScribeGlow.edgeBrightness(t: t) : 0.35
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.clear
                if height > 0.001 {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(scribeColor(ScribeGlow.edgeColor))
                            .frame(height: 2)
                            .opacity(edge)
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [scribeColor(ScribeGlow.peakColor).opacity(0.85), scribeColor(ScribeGlow.washColor).opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                    }
                    .frame(height: proxy.size.height * CGFloat(height))
                    .blur(radius: 8)
                }
            }
        }
        .opacity(opacity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: States

/// An accessibility element that VoiceOver is sent to whenever `focusToken` changes (a new state heading).
/// Posting `.layoutChanged` with the element is the documented way to direct VoiceOver focus on macOS.
struct ScribeAccessibilityFocusAnchor: NSViewRepresentable {
    let label: String
    let focusToken: Int

    final class AnchorView: NSView {
        var label = ""
        /// The newest token handed to this view; a token is requested once.
        var requestedToken: Int?
        /// A requested token not yet posted. Stays set until the view is in a window, then is posted exactly once.
        var pendingToken: Int?

        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
        override func accessibilityLabel() -> String? { label }

        func request(_ token: Int) {
            guard requestedToken != token else { return }
            requestedToken = token
            pendingToken = token
            DispatchQueue.main.async { [weak self] in self?.postPendingIfAttached() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, pendingToken != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.postPendingIfAttached() }
        }

        /// Without a window the token stays pending; `viewDidMoveToWindow` retries it.
        private func postPendingIfAttached() {
            guard pendingToken != nil, window != nil else { return }
            pendingToken = nil
            NSAccessibility.post(element: self, notification: .layoutChanged, userInfo: [.uiElements: [self]])
        }
    }

    func makeNSView(context: Context) -> AnchorView { AnchorView() }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.label = label
        view.request(focusToken)
    }
}

private struct ScribeHeader: View {
    let title: String
    var trailing: String?
    /// When set, the heading also carries the focus anchor for this state.
    var focusToken: Int?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.and.mic").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.cloudPrimary)
            Text(title).font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
            Spacer()
            if let trailing {
                Text(trailing).font(TopBarStyle.label(11, .semibold).monospacedDigit()).foregroundStyle(Theme.cloudSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        // The anchor speaks the heading, so the header itself is hidden from VoiceOver to avoid a double read.
        .accessibilityHidden(focusToken != nil)
        .background {
            if let focusToken {
                ScribeAccessibilityFocusAnchor(label: title, focusToken: focusToken)
            }
        }
    }
}

/// The second step of "Delete permanently": says exactly what is removed, and that it can't be undone.
struct ScribeDeleteConfirm: View {
    let scribe: ScribeController
    let id: ScribeSessionID

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Delete this meeting permanently? Its notes, transcript and private notes are removed from this Mac and can't be recovered.")
                .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                NotchActionButton(title: "Delete permanently", tint: TopBarStyle.rec) { scribe.deletePermanently(id) }
                NotchActionButton(title: "Keep", tint: Theme.cloudSecondary, filled: false) { scribe.cancelDelete() }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// A saved meeting opened from the list.
private struct ScribeRecapDetail: View {
    let scribe: ScribeController

    var body: some View {
        if let recap = scribe.openedRecap {
            ScribeMeetingBody(
                title: recap.title,
                duration: recap.duration,
                endedAt: recap.endedAt,
                notes: recap.notes,
                transcript: recap.transcript,
                warnings: [recap.transcriptionNote, recap.micExcludedDuringCall ? ScribeMicCallText.recapLine : nil].compactMap { $0 },
                focusToken: scribe.focusToken,
                closeTitle: "Back",
                speakerTools: scribe.speakerTools(for: recap.id),
                setPrivateNotes: { scribe.setPrivateNotes($0, for: recap.id) },
                setActionItem: { scribe.setActionItem($0, done: $1, for: recap.id) },
                close: { scribe.closeRecap() },
                actions: {
                    if scribe.pendingDeleteID == recap.id {
                        ScribeDeleteConfirm(scribe: scribe, id: recap.id)
                    } else {
                        NotchActionButton(title: "Delete permanently", tint: Theme.cloudSecondary, filled: false) {
                            scribe.requestDelete(recap.id)
                        }
                    }
                }
            )
        }
    }
}

private struct ScribeConnecting: View {
    let scribe: ScribeController
    let state: ScribePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScribeHeader(title: "Scribe", focusToken: scribe.focusToken)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting…").font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(state.accessibilityLabel)
            .accessibilityValue(state.accessibilityValue)
            Spacer(minLength: 0)
            NotchActionButton(title: "Cancel", tint: Theme.cloudSecondary, filled: false) { scribe.cancel() }
        }
    }
}

/// Seven elements that follow the audio: small white dots while it is quiet, green bars scaled by level when
/// it isn't. Reduce Motion draws one steady set of bars instead. Shared by the page and the closed-notch wings.
struct ScribeMeterView: View {
    let history: [Double]
    var height: CGFloat = 18
    var barWidth: CGFloat = 3.5
    var spacing: CGFloat = 3
    var reduceMotion = false

    private static let steady: [Double] = [0.3, 0.5, 0.7, 0.9, 0.7, 0.5, 0.3]

    var body: some View {
        let bars = reduceMotion ? Self.steady : ScribeLevelMeter.bars(history: history)
        HStack(alignment: .center, spacing: spacing) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, level in
                if level < ScribeLevelMeter.silentBelow {
                    Circle().fill(Color.white.opacity(0.85)).frame(width: barWidth, height: barWidth)
                } else {
                    Capsule().fill(Theme.leaf).frame(width: barWidth, height: max(barWidth, height * CGFloat(min(1, level))))
                }
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .linear(duration: 0.06), value: bars)
        .accessibilityHidden(true)
    }
}

/// The meter and the clock, spoken as one status.
private struct ScribeRecordingStatus: View {
    let state: ScribePresentation
    let elapsed: TimeInterval
    let history: [Double]
    var reduceMotion = false

    var body: some View {
        HStack(spacing: 10) {
            ScribeMeterView(history: history, reduceMotion: reduceMotion)
            Text(RecordlyElapsed.format(elapsed))
                .font(TopBarStyle.label(13, .medium).monospacedDigit())
                .foregroundStyle(Theme.cloudSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(state.accessibilityValue)
    }
}

/// A round icon button for the recording toolbar.
private struct ScribeCircleButton: View {
    let symbol: String
    let label: String
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.cloudPrimary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}

private struct ScribeRecording: View {
    let scribe: ScribeController
    let state: ScribePresentation
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            toolbar
            ScribeLiveStatusRow(scribe: scribe, reduceMotion: reduceMotion)
            if let note = scribe.systemAudioNote {
                ScribeIssueLine(text: note, lineLimit: 2)
            }
            if let note = scribe.microphoneNote {
                ScribeIssueLine(text: note, lineLimit: 2)
            }
            if scribe.systemAudioStalled {
                ScribeIssueLine(text: ScribeSystemStall.warningText, lineLimit: 2)
            }
            if let issue = scribe.transcriptionIssue {
                ScribeIssueLine(text: issue, lineLimit: 2)
            }
            ScribeLiveTranscript(scribe: scribe, reduceMotion: reduceMotion)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The square Stop control, the live dot and the clock (the only red on the page), and discard.
    @ViewBuilder
    private var toolbar: some View {
        if scribe.discardRequested {
            HStack(spacing: 10) {
                // VoiceOver lands on the question (the Trash button that was focused is gone).
                Text(ScribeController.discardQuestion)
                    .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary)
                    .lineLimit(2)
                    .accessibilityHidden(true)
                    .background { ScribeAccessibilityFocusAnchor(label: ScribeController.discardQuestion, focusToken: scribe.focusToken) }
                Spacer(minLength: 0)
                NotchActionButton(title: "Discard", tint: Theme.ember) { scribe.confirmDiscard() }
                    .accessibilityHint("Stops recording and permanently throws this meeting away.")
                NotchActionButton(title: "Keep recording", tint: Theme.cloudSecondary, filled: false) {
                    scribe.keepAfterDiscardRequest()
                }
            }
            .frame(minHeight: 40)
        } else {
            HStack(spacing: 10) {
                stopControl
                ScribeLiveClock(state: state, elapsed: scribe.elapsed)
                Spacer(minLength: 0)
                ScribeCircleButton(symbol: "trash", label: "Discard recording", hint: "Asks before throwing this meeting away.") {
                    scribe.requestDiscard()
                }
            }
            .frame(minHeight: 40)
            .background { ScribeAccessibilityFocusAnchor(label: "Scribe, listening", focusToken: scribe.focusToken) }
        }
    }

    private var stopControl: some View {
        RecordlyCaptureControl(
            visual: .recording, enabled: true, countdownBeganAt: nil,
            help: "Stop recording", spokenSource: nil,
            idleSymbol: "waveform", idleLabel: "Start Scribe", stopLabel: "Stop recording"
        ) { scribe.requestEnd() }
        .accessibilityHint("Asks whether to end the meeting.")
        .scaleEffect(0.72)
        .frame(width: 40, height: 40)
        .ownedJourneyControl("scribe.stop")
    }
}

/// The live dot and the elapsed time, spoken as one status. Red marks capturing right now, nothing else.
private struct ScribeLiveClock: View {
    let state: ScribePresentation
    let elapsed: TimeInterval

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(TopBarStyle.rec).frame(width: 8, height: 8)
            Text("Recording")
                .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudSecondary)
            Text(RecordlyElapsed.format(elapsed))
                .font(TopBarStyle.label(20, .semibold).monospacedDigit())
                .foregroundStyle(TopBarStyle.rec)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(state.accessibilityValue)
    }
}

/// Which audio is actually being kept: the microphone gate (from the router's own reading) and system audio.
struct ScribeInputStatus: View {
    let scribe: ScribeController

    var body: some View {
        let mic = scribe.micIndicator
        let system = scribe.systemIndicator
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Image(systemName: mic.isRecorded ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(mic.isRecorded ? TopBarStyle.rec : Theme.ember)
                Text(mic.label).font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudPrimary)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 5) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.cloudSecondary)
                Text(system.label).font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// The live transcript while recording: every line has its speaker (tinted), its time and its text, newest at
/// the bottom with the list following it. Provisional text is dimmed; final text is solid. The newest changed
/// line reveals a few words at a time.
private struct ScribeLiveTranscript: View {
    let scribe: ScribeController
    let reduceMotion: Bool

    var body: some View {
        DisplaySynchronizedView(paused: reduceMotion || scribe.incomingWordsRevealUntil == nil,
            preferredFramesPerSecond: 240, until: scribe.incomingWordsRevealUntil) { context in
            ScribeLiveTranscriptContent(scribe: scribe, date: context.date, reduceMotion: reduceMotion)
        }
    }
}

private struct ScribeLiveTranscriptContent: View {
    let scribe: ScribeController
    let date: Date
    let reduceMotion: Bool

    private static let bottomID = "scribe-live-bottom"

    var body: some View {
        let segments = scribe.liveSegments(limit: 60)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if segments.isEmpty {
            Text("Listening… text appears as people speak.")
                .font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if TopBarStyle.isSnapshot {
            // ImageRenderer can't draw scroll views: show the newest lines flat.
            lines(Array(segments.suffix(4)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        } else {
            let key = followKey(segments)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        lines(segments)
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // A page opened mid-meeting starts at the newest line, not the top.
                .onAppear { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                .onChange(of: key) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                        proxy.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func lines(_ segments: [ScribeTranscriptSegment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments, id: \.id) { segment in
                let shown = scribe.visibleWordCount(for: segment, at: date, reduceMotion: reduceMotion)
                let layout = scribe.incomingWordLayout(for: segment)
                let settling = !reduceMotion && layout?.isSettled(at: date.timeIntervalSinceReferenceDate, shownWords: shown) == false
                ScribeLiveLine(
                    segment: segment,
                    shownWords: shown, wordLayout: settling ? layout : nil,
                    date: settling ? date : .distantPast, reduceMotion: reduceMotion
                )
                .equatable()
            }
        }
    }

    /// Changes whenever anything that can change the list's height does: a line added, any line's text or
    /// finality replaced, or any line showing another word. So an earlier line growing still keeps the list following.
    private func followKey(_ segments: [ScribeTranscriptSegment]) -> Int {
        var hasher = Hasher()
        hasher.combine(segments.count)
        for segment in segments {
            hasher.combine(segment.id)
            hasher.combine(segment.text)
            hasher.combine(segment.isFinal)
            hasher.combine(scribe.visibleWordCount(for: segment, at: date, reduceMotion: reduceMotion))
        }
        return hasher.finalize()
    }
}

/// One transcript line: speaker and time on top, the text beneath.
private struct ScribeLiveLine: View, Equatable {
    let segment: ScribeTranscriptSegment
    let shownWords: Int
    let wordLayout: ScribeIncomingWordLayout?
    let date: Date
    let reduceMotion: Bool

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.segment == rhs.segment && lhs.shownWords == rhs.shownWords
            && lhs.wordLayout?.revision == rhs.wordLayout?.revision
            && lhs.date == rhs.date && lhs.reduceMotion == rhs.reduceMotion
    }

    var body: some View {
        let tint = scribeColor(ScribeSpeakerPalette.color(for: segment.speaker))
        let time = RecordlyElapsed.format(max(0, segment.start))
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                // A chip in the speaker's colour, the same one the closed-notch ticker and the finished notes use.
                HStack(spacing: 4) {
                    Circle().fill(tint).frame(width: 5, height: 5)
                    Text(segment.speaker.displayName)
                        .font(TopBarStyle.label(10, .semibold)).foregroundStyle(tint)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(tint.opacity(0.14)))
                Spacer(minLength: 0)
                Text(time)
                    .font(TopBarStyle.label(9).monospacedDigit()).foregroundStyle(Theme.cloudQuiet)
            }
            Group {
                if #available(macOS 15.0, *), let wordLayout {
                    ScribeIncomingWords(layout: wordLayout, shownWords: shownWords, date: date, reduceMotion: reduceMotion)
                } else {
                    Text(ScribeWordText.prefix(segment.text, words: shownWords))
                }
            }
                .font(TopBarStyle.label(12))
                .foregroundStyle(segment.isFinal ? Theme.cloudPrimary : Theme.cloudPrimary.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(segment.speaker.displayName), \(time)")
        .accessibilityValue(segment.isFinal ? segment.text : "\(segment.text), provisional")
    }
}

private struct ScribeConfirmEnd: View {
    let topBar: TopBarModel
    let scribe: ScribeController
    let state: ScribePresentation

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 10) {
                ScribeHeader(title: "Scribe")
                ScribeRecordingStatus(state: state, elapsed: scribe.elapsed, history: scribe.levelHistory)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .opacity(0.35)
            .accessibilityHidden(true)
            VStack(spacing: 8) {
                let heading = scribe.endStopRequested ? "Finishing recording…"
                    : "Meeting ending in \(scribe.endingRemaining ?? 9)s"
                Text(heading).font(TopBarStyle.label(14, .semibold)).foregroundStyle(Theme.cloudPrimary)
                    .accessibilityHidden(true)
                    .background { ScribeAccessibilityFocusAnchor(label: heading, focusToken: scribe.focusToken) }
                Text(scribe.endingReason == .boundCallAppClosed
                     ? "The call app closed. Keep recording to continue this meeting."
                     : "You asked to stop. Keep recording to cancel the countdown.")
                    .font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary)
                HStack(spacing: 10) {
                    NotchActionButton(title: "End meeting now", tint: TopBarStyle.rec) {
                        scribe.confirmEnd()
                        // The end animation plays on this page: keep it the open one.
                        topBar.onOpenTab(.scribe)
                    }
                    .disabled(scribe.endStopRequested)
                    .accessibilityIdentifier("scribe.endNow")
                    NotchActionButton(title: "Keep recording", tint: Theme.cloudSecondary, filled: false) { scribe.keepRecording() }
                        .disabled(scribe.endStopRequested)
                        .accessibilityIdentifier("scribe.keep")
                }
                .padding(.top, 4)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(state.accessibilityLabel)
            .accessibilityValue(scribe.endStopRequested ? "Finishing recording" : "\(scribe.endingRemaining ?? 9) seconds remaining")
        }
    }
}

/// Empty body with a bottom glow (drawn by the stage) and a label, for as long as the notes take.
private struct ScribeWriting: View {
    let scribe: ScribeController
    let state: ScribePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScribeHeader(title: "Meeting notes", trailing: RecordlyElapsed.format(scribe.elapsed), focusToken: scribe.focusToken)
            if let reason = scribe.stoppedEarlyReason {
                ScribeIssueLine(text: "\(ScribeRecapNote.stoppedEarlyPrefix): \(reason) What was captured is being saved.")
            }
            Spacer(minLength: 0)
            Text("Writing notes…")
                .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudSecondary)
                .accessibilityLabel(state.accessibilityLabel)
                .accessibilityValue(state.accessibilityValue)
            NotchActionButton(title: "Stop and save transcript", tint: Theme.cloudSecondary, filled: false) {
                scribe.cancelProcessing()
            }
            .accessibilityHint("Stops waiting for the notes and saves what was transcribed so far, without notes.")
            .padding(.bottom, 14)
        }
    }
}

/// The notes of the meeting that just finished.
private struct ScribeNotesView: View {
    let scribe: ScribeController

    /// Speaker naming once the meeting is saved as a recap; until then there is nothing to rename.
    private func namingTools(_ id: ScribeSessionID?) -> ScribeSpeakerTools? {
        guard let id, scribe.recaps.contains(where: { $0.id == id }) else { return nil }
        return scribe.speakerTools(for: id)
    }

    var body: some View {
        let id = scribe.phase.sessionID
        let note = ScribeRecapNote.compose(
            issues: scribe.transcriptionIssues, stoppedEarly: scribe.stoppedEarlyReason, notesIssue: scribe.notesIssue
        )
        // The recap exists once the notes are ready; until then there is no end time to show.
        let endedAt = scribe.recaps.first { $0.id == id }?.endedAt
        ScribeMeetingBody(
            title: "Meeting notes",
            duration: scribe.elapsed,
            endedAt: endedAt,
            notes: scribe.notes ?? ScribeMeetingNotes(),
            transcript: scribe.transcript?.finalSegments ?? [],
            warnings: [note, scribe.micExcludedDuringCall ? ScribeMicCallText.excludedNotice : nil].compactMap { $0 },
            focusToken: scribe.focusToken,
            closeTitle: "Done",
            speakerTools: namingTools(id),
            setPrivateNotes: { text in
                if let id { scribe.setPrivateNotes(text, for: id) }
            },
            setActionItem: { index, done in
                if let id { scribe.setActionItem(index, done: done, for: id) }
            },
            close: { scribe.closeNotes() },
            actions: { EmptyView() }
        )
    }
}

/// The finished notes' look: one lavender family (the writing glow's own edge purple) that settles from a
/// tinted summary card into soft neutral cards, so the page ends calm after the glow.
enum ScribeNotesStyle {
    static let accent = scribeColor(ScribeGlow.edgeColor)
    static let cardFill = Color.white.opacity(0.06)
    static let cardRim = Color.white.opacity(0.08)
    static var prominentFill: LinearGradient {
        LinearGradient(
            colors: [scribeColor(ScribeGlow.washColor).opacity(0.38), Color.white.opacity(0.06)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// What a finished meeting offers for naming its speakers; nil where naming is not possible.
struct ScribeSpeakerTools {
    var suggestions: [ScribeNameSuggestion]
    var attendeeNames: [String]
    /// Who named each speaker and how sure Zeus is (saved with the meeting).
    var identities: [ScribeSpeakerIdentity] = []
    /// Tiny voices were folded into other speakers at the end of the meeting and can be put back.
    var hasPrunedVoices = false
    /// What Undo would undo ("Undo merge"), nil when there is nothing to undo.
    var undoTitle: String?
    /// True while naming can still happen, so an unresolved voice reads "Identifying this speaker...".
    var isIdentifying = false
    var canRemember: (ScribeSpeaker) -> Bool
    /// The speaker, the name typed, and whether "Remember this voice" was ticked.
    var rename: (ScribeSpeaker, String, Bool) -> Void
    /// Accepts a suggested name (its source is kept: the invite or what was said).
    var accept: (ScribeSpeaker, String) -> Void
    var confirm: (ScribeSpeaker) -> Void
    var notThem: (ScribeSpeaker) -> Void
    /// Segment id and the name the block should go to.
    var reassignBlock: (String, String) -> Void
    /// Segment id, the word range, and the name those words should go to.
    var assignWords: (String, Range<Int>, String) -> Void
    var undo: () -> Void
    var restorePruned: () -> Void
    var copyTranscript: () -> Void
    /// Plays a short clip of a speaker. Nil while Zeus keeps no meeting audio, which hides the play button.
    var playSample: ((ScribeSpeaker) -> Void)?

    func identity(of speaker: ScribeSpeaker) -> ScribeSpeakerIdentity? {
        identities.first { ScribeSpeakerNames.key($0.name) == ScribeSpeakerNames.key(speaker.displayName) }
    }
}

/// One speaker of the meeting: colour dot, name, talk time and a thin bar for their share of the talking.
/// With tools, the name is a button: tap it, type a name, press Return. A suggestion shows as "Name?" with Accept.
private struct ScribeSpeakerRow: View {
    let entry: ScribeSpeakerStats.Entry
    var tools: ScribeSpeakerTools?
    /// This speaker's longest lines, so the person can tell who it was (audio is never kept).
    var lines: [String] = []
    /// Names already used by other speakers or on the invite, offered as one-tap answers.
    var quickNames: [String] = []

    @State private var editing = false
    @State private var draft = ""
    @State private var remember = false

    private var canRename: Bool { tools != nil && entry.speaker != .you }

    var body: some View {
        let tint = scribeColor(ScribeSpeakerPalette.color(for: entry.speaker))
        let time = ScribeSpeakerStats.format(entry.talkSeconds)
        let percent = Int((entry.share * 100).rounded())
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                if canRename {
                    Button { startEditing() } label: {
                        Text(shownName)
                            .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                            .overlay(alignment: .bottom) { unconfirmedUnderline }
                    }
                    .buttonStyle(.plain)
                    .help("Rename this speaker")
                    .accessibilityLabel("\(entry.speaker.displayName), rename")
                } else {
                    Text(entry.speaker.displayName)
                        .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                }
                if let suggestion = suggestion, !editing {
                    Button { tools?.accept(entry.speaker, suggestion.name) } label: {
                        Text("\(suggestion.name)? Accept")
                            .font(TopBarStyle.label(10, .semibold)).foregroundStyle(ScribeNotesStyle.accent).lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().strokeBorder(ScribeNotesStyle.accent.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Accept the name \(suggestion.name) for \(entry.speaker.displayName)")
                }
                Spacer(minLength: 0)
                Text(time).font(TopBarStyle.label(10).monospacedDigit()).foregroundStyle(Theme.cloudSecondary)
                Text("\(percent)%")
                    .font(TopBarStyle.label(10).monospacedDigit()).foregroundStyle(Theme.cloudSecondary)
                    .frame(width: 32, alignment: .trailing)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(tint)
                        .frame(width: max(3, proxy.size.width * CGFloat(min(1, max(0, entry.share)))))
                }
            }
            .frame(height: 3)
            identityLine
            if editing { editor }
        }
        .accessibilityElement(children: editing ? .contain : .ignore)
        .accessibilityLabel(entry.speaker.displayName)
        .accessibilityValue("\(time), \(percent) percent of the talking")
    }

    private var suggestion: ScribeNameSuggestion? {
        tools?.suggestions.first { $0.speaker == entry.speaker }
    }

    private var identity: ScribeSpeakerIdentity? { tools?.identity(of: entry.speaker) }

    /// The name, or "Identifying this speaker..." for a voice still unnamed while naming can happen.
    private var shownName: String {
        ScribeSpeakerCaption.name(for: entry.speaker, identifying: tools?.isIdentifying ?? false).text
    }

    /// A dotted line under a name Zeus chose and the person has not confirmed.
    @ViewBuilder private var unconfirmedUnderline: some View {
        if identity?.needsConfirmation == true {
            Rectangle().fill(Color.clear).frame(height: 1)
                .overlay(Rectangle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2])).foregroundStyle(ScribeNotesStyle.accent))
        }
    }

    /// Where the name came from, and Confirm / Not them for one that is not confirmed yet.
    @ViewBuilder private var identityLine: some View {
        if let identity, !editing {
            HStack(spacing: 8) {
                Text(identity.confirmed ? identity.source.caption : "\(identity.source.caption), not confirmed")
                    .font(TopBarStyle.label(9)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
                if !identity.confirmed {
                    Button("Confirm") { tools?.confirm(entry.speaker) }
                        .buttonStyle(.plain)
                        .font(TopBarStyle.label(9, .semibold)).foregroundStyle(ScribeNotesStyle.accent)
                        .accessibilityLabel("Confirm the name \(identity.name)")
                    Button("Not them") { tools?.notThem(entry.speaker) }
                        .buttonStyle(.plain)
                        .font(TopBarStyle.label(9, .semibold)).foregroundStyle(Theme.cloudSecondary)
                        .accessibilityLabel("\(identity.name) is not this speaker")
                }
            }
        }
    }

    @ViewBuilder private var editor: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text("\u{201C}\(line)\u{201D}")
                    .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let play = tools?.playSample {
                Button("Play 3 seconds") { play(entry.speaker) }
                    .buttonStyle(.plain)
                    .font(TopBarStyle.label(10, .semibold)).foregroundStyle(ScribeNotesStyle.accent)
                    .accessibilityLabel("Play a short sample of \(entry.speaker.displayName)")
            }
            TextField("Name", text: $draft)
                .textFieldStyle(.plain)
                .font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudPrimary)
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.18)))
                .onSubmit { commit() }
                .accessibilityLabel("Name for \(entry.speaker.displayName)")
            if !quickNames.isEmpty {
                HStack(spacing: 4) {
                    ForEach(quickNames.prefix(4), id: \.self) { name in
                        Button(name) { draft = name }
                            .buttonStyle(.plain)
                            .font(TopBarStyle.label(10)).foregroundStyle(ScribeNotesStyle.accent).lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().strokeBorder(ScribeNotesStyle.accent.opacity(0.4), lineWidth: 1))
                    }
                }
            }
            if tools?.canRemember(entry.speaker) == true {
                Toggle(isOn: $remember) {
                    Text("Remember this voice on this Mac").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudPrimary)
                }
                .toggleStyle(.checkbox)
                Text("Only save voices of people who agreed.")
                    .font(TopBarStyle.label(9)).foregroundStyle(Theme.cloudSecondary)
            }
            HStack(spacing: 6) {
                NotchActionButton(title: "Save name", tint: TopBarStyle.rec) { commit() }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                NotchActionButton(title: "Cancel", tint: Theme.cloudSecondary, filled: false) { editing = false }
            }
        }
        .padding(.top, 3)
    }

    private func startEditing() {
        draft = ""
        remember = false
        editing = true
    }

    private func commit() {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        tools?.rename(entry.speaker, name, remember && tools?.canRemember(entry.speaker) == true)
        editing = false
    }
}

/// Summary, decisions, action items, editable private notes and the transcript of one meeting.
private struct ScribeMeetingBody<Actions: View>: View {
    let title: String
    let duration: TimeInterval
    let endedAt: Date?
    let notes: ScribeMeetingNotes
    let transcript: [ScribeTranscriptSegment]
    let warnings: [String]
    let focusToken: Int
    let closeTitle: String
    let speakerTools: ScribeSpeakerTools?
    let setPrivateNotes: (String) -> Void
    let setActionItem: (Int, Bool) -> Void
    let close: () -> Void
    let actions: Actions

    init(
        title: String,
        duration: TimeInterval,
        endedAt: Date? = nil,
        notes: ScribeMeetingNotes,
        transcript: [ScribeTranscriptSegment],
        warnings: [String],
        focusToken: Int,
        closeTitle: String,
        speakerTools: ScribeSpeakerTools? = nil,
        setPrivateNotes: @escaping (String) -> Void,
        setActionItem: @escaping (Int, Bool) -> Void,
        close: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.duration = duration
        self.endedAt = endedAt
        self.notes = notes
        self.transcript = transcript
        self.warnings = warnings
        self.focusToken = focusToken
        self.closeTitle = closeTitle
        self.speakerTools = speakerTools
        self.setPrivateNotes = setPrivateNotes
        self.setActionItem = setActionItem
        self.close = close
        self.actions = actions()
    }

    var body: some View {
        let stats = ScribeSpeakerStats(segments: transcript)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.and.mic").font(.system(size: 12, weight: .bold)).foregroundStyle(ScribeNotesStyle.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(TopBarStyle.label(13, .semibold)).foregroundStyle(Theme.cloudPrimary)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                        .background { ScribeAccessibilityFocusAnchor(label: title, focusToken: focusToken) }
                    Text(metaLine).font(TopBarStyle.label(10).monospacedDigit()).foregroundStyle(Theme.cloudSecondary)
                        .lineLimit(1)
                }
                Spacer()
                actions
                NotchActionButton(title: closeTitle, tint: Theme.cloudSecondary, filled: false) { close() }
                    .ownedJourneyControl("scribe.notes.close")
            }
            HStack(alignment: .top, spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                            ScribeIssueLine(text: warning)
                        }
                        // The one prominent card: the purple of the writing glow, settling into the neutral cards below.
                        card("Summary", prominent: true) {
                            Text(notes.summary.isEmpty ? "Nothing was said that Scribe could summarize." : notes.summary)
                                .font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        card("Action items") { actionItemRows }
                        card("Decisions") { bullets(notes.decisions, empty: "None found.") }
                        if stats.isWorthShowing {
                            card("Speakers") {
                                speakerHistoryControls
                                ForEach(Array(stats.speakers.enumerated()), id: \.offset) { _, entry in
                                    ScribeSpeakerRow(
                                        entry: entry, tools: speakerTools,
                                        lines: Self.longestLines(of: entry.speaker, in: transcript),
                                        quickNames: quickNames(excluding: entry.speaker, stats: stats)
                                    )
                                }
                            }
                        }
                        card("Private notes") {
                            TextEditor(text: Binding(get: { notes.privateNotes }, set: { setPrivateNotes($0) }))
                                .font(TopBarStyle.label(11))
                                .foregroundStyle(Theme.cloudPrimary)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 70)
                                .padding(4)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.18)))
                                .accessibilityLabel("Private notes")
                                .accessibilityHint("Only you see these. They are saved on this Mac.")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                transcriptList
                    .frame(width: 300, alignment: .topLeading)
            }
        }
    }

    /// The speaker's three longest lines, shortened: what the rename editor shows instead of an audio clip.
    private static func longestLines(of speaker: ScribeSpeaker, in transcript: [ScribeTranscriptSegment]) -> [String] {
        var lines: [String] = []
        for segment in transcript where segment.speaker == speaker {
            lines.append(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        lines.sort { (a: String, b: String) -> Bool in a.count > b.count }
        var shortened: [String] = []
        for line in lines.prefix(3) {
            shortened.append(line.count > 90 ? String(line.prefix(90)) + "\u{2026}" : line)
        }
        return shortened
    }

    /// Invitee names not yet taken by a speaker, then the other speakers' names (naming one the same merges them).
    private func quickNames(excluding speaker: ScribeSpeaker, stats: ScribeSpeakerStats) -> [String] {
        guard let speakerTools else { return [] }
        let taken = Set(stats.speakers.map { ScribeSpeakerNames.key($0.speaker.displayName) })
        return speakerTools.attendeeNames.filter { !taken.contains(ScribeSpeakerNames.key($0)) }
    }

    /// Names a block can be reassigned to: the meeting's speakers (not "You" twice), then the invite.
    private var blockNames: [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for entry in ScribeSpeakerStats(segments: transcript).speakers {
            let name = entry.speaker.displayName
            if entry.speaker != .unknown, seen.insert(ScribeSpeakerNames.key(name)).inserted { names.append(name) }
        }
        for name in speakerTools?.attendeeNames ?? [] where seen.insert(ScribeSpeakerNames.key(name)).inserted { names.append(name) }
        return names
    }

    /// Undo for the last speaker change, and a way to put folded tiny voices back.
    @ViewBuilder private var speakerHistoryControls: some View {
        if let tools = speakerTools, tools.undoTitle != nil || tools.hasPrunedVoices {
            HStack(spacing: 10) {
                if let title = tools.undoTitle {
                    Button(title) { tools.undo() }
                        .buttonStyle(.plain)
                        .font(TopBarStyle.label(10, .semibold)).foregroundStyle(ScribeNotesStyle.accent)
                        .accessibilityHint("Brings back the speakers as they were before the last change.")
                }
                if tools.hasPrunedVoices {
                    Button("Restore small voices") { tools.restorePruned() }
                        .buttonStyle(.plain)
                        .font(TopBarStyle.label(10, .semibold)).foregroundStyle(ScribeNotesStyle.accent)
                        .accessibilityHint("Puts back the very short voices Zeus folded into other speakers.")
                }
            }
        }
    }

    /// The date it ended (when known) and how long it ran.
    private var metaLine: String {
        let length = RecordlyElapsed.format(duration)
        guard let endedAt else { return length }
        return "\(endedAt.formatted(date: .abbreviated, time: .shortened)) · \(length)"
    }

    @ViewBuilder
    private var actionItemRows: some View {
        if notes.actionItems.isEmpty {
            Text("None found.").font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary)
        } else {
            ForEach(Array(notes.actionItems.enumerated()), id: \.offset) { index, item in
                Button { setActionItem(index, !item.done) } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: item.done ? "checkmark.square.fill" : "square")
                            .font(.system(size: 11)).foregroundStyle(item.done ? Theme.cloudSecondary : ScribeNotesStyle.accent)
                        Text(item.text).font(TopBarStyle.label(11))
                            .strikethrough(item.done)
                            .foregroundStyle(item.done ? Theme.cloudSecondary : Theme.cloudPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.text)
                .accessibilityValue(item.done ? "Done" : "Not done")
                .accessibilityHint("Toggles done.")
            }
        }
    }

    private func card<Inner: View>(_ title: String, prominent: Bool = false, @ViewBuilder _ inner: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(TopBarStyle.label(10, .semibold)).foregroundStyle(ScribeNotesStyle.accent)
                .accessibilityAddTraits(.isHeader)
            inner()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background {
            if prominent {
                RoundedRectangle(cornerRadius: 10).fill(ScribeNotesStyle.prominentFill)
            } else {
                RoundedRectangle(cornerRadius: 10).fill(ScribeNotesStyle.cardFill)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(prominent ? ScribeNotesStyle.accent.opacity(0.28) : ScribeNotesStyle.cardRim, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func bullets(_ items: [String], empty: String) -> some View {
        if items.isEmpty {
            Text(empty).font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary)
        } else {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").font(TopBarStyle.label(11, .bold)).foregroundStyle(ScribeNotesStyle.accent)
                        .accessibilityHidden(true)
                    Text(item).font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var transcriptList: some View {
        let segments = transcript
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Transcript").font(TopBarStyle.label(10, .semibold)).foregroundStyle(ScribeNotesStyle.accent)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let speakerTools, !segments.isEmpty {
                    Button("Copy") { speakerTools.copyTranscript() }
                        .buttonStyle(.plain)
                        .font(TopBarStyle.label(10, .semibold)).foregroundStyle(ScribeNotesStyle.accent)
                        .accessibilityLabel("Copy the transcript with speaker names")
                }
            }
            if segments.isEmpty {
                Text("No transcript was captured.").font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(segments, id: \.id) { segment in
                            ScribeTranscriptBlock(segment: segment, tools: speakerTools, names: blockNames)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(ScribeNotesStyle.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ScribeNotesStyle.cardRim, lineWidth: 1))
    }
}

private struct ScribeFailed: View {
    let scribe: ScribeController
    let reason: String
    let state: ScribePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScribeHeader(title: "Scribe", focusToken: scribe.focusToken)
            Text(reason)
                .font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(state.accessibilityLabel)
                .accessibilityValue(state.accessibilityValue)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                NotchActionButton(title: "Try again", tint: TopBarStyle.rec) { scribe.retry() }
                NotchActionButton(title: "Dismiss", tint: Theme.cloudSecondary, filled: false) { scribe.closeNotes() }
            }
        }
    }
}
