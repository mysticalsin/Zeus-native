import SwiftUI
import ZeusCore

/// Scribe's tab. The stage (idle, recording, writing, notes ...) changes only on session-machine events;
/// the TimelineView only supplies a clock for drawing the glow and wash from the stage's start time.
struct ScribePage: View {
    let topBar: TopBarModel
    let scribe: ScribeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
                Tile {
                    // While recording only the word reveal needs the clock, so it ticks at 20 Hz; the glow
                    // stages (writing, reveal) draw at the display rate.
                    let pacing: Double? = { if case .recording = scribe.phase { return 1.0 / 20 }; return nil }()
                    TimelineView(.animation(minimumInterval: pacing, paused: !scribe.needsFrameClock)) { context in
                        ScribeStage(topBar: topBar, scribe: scribe, date: context.date, reduceMotion: reduceMotion)
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
private struct ScribeIssueLine: View {
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

private func scribeColor(_ rgb: ScribeGlow.RGB) -> Color {
    Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
}

private struct ScribeStage: View {
    let topBar: TopBarModel
    let scribe: ScribeController
    let date: Date
    let reduceMotion: Bool

    var body: some View {
        let state = scribe.presentation(at: date, reduceMotion: reduceMotion)
        let stage = state.glowStage
        let glowTime = stage == .reveal ? scribe.revealElapsed(at: date) : scribe.stageElapsed(at: date)
        ZStack(alignment: .bottom) {
            content(state)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if stage != .off {
                ScribeGlowLayer(stage: stage, t: glowTime, reduceMotion: reduceMotion)
            }
        }
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
            ScribeRecording(scribe: scribe, state: state, date: date, reduceMotion: reduceMotion)
        case .confirmingEnd:
            ScribeConfirmEnd(topBar: topBar, scribe: scribe, state: state)
        case .writing:
            ScribeWriting(scribe: scribe, state: state)
        case .revealing:
            ScribeNotesView(scribe: scribe)
                .opacity(ScribeGlow.contentOpacity(t: scribe.revealElapsed(at: date), reduceMotion: reduceMotion))
        case .complete:
            ScribeNotesView(scribe: scribe)
        case .failed(let reason):
            ScribeFailed(scribe: scribe, reason: reason, state: state)
        }
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
private struct ScribeAccessibilityFocusAnchor: NSViewRepresentable {
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

private struct ScribeIdle: View {
    let scribe: ScribeController

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                ScribeHeader(title: "Scribe", focusToken: scribe.focusToken)
                Text("Listens to a meeting and writes your notes when it ends.")
                    .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let disclosure = scribe.cloudDisclosure {
                    ScribeIssueLine(text: disclosure)
                }
                if let note = scribe.availabilityNote {
                    Text(note)
                        .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Availability: \(note)")
                }
                Spacer(minLength: 0)
                NotchActionButton(title: "Start", tint: TopBarStyle.rec) { scribe.start() }
                    .accessibilityHint("Starts listening to a meeting.")
                    .accessibilityIdentifier("scribe.start")
            }
            .frame(width: 270, alignment: .topLeading)
            ScribeRecapList(scribe: scribe)
        }
    }
}

private struct ScribeRecapList: View {
    let scribe: ScribeController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Recent meetings").font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                NotchActionButton(title: "Memory", tint: Theme.cloudSecondary, filled: false) { WikiController.shared.showWindow() }
                    .accessibilityHint("Opens what Zeus has learned from your meetings.")
            }
            if scribe.recaps.isEmpty {
                Text("Finished meetings and their notes show up here.")
                    .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(scribe.recaps) { recap in
                            ScribeRecapRow(scribe: scribe, recap: recap)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ScribeRecapRow: View {
    let scribe: ScribeController
    let recap: ScribeRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Button { scribe.openRecap(recap.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(recap.title).font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                            Text(recap.endedAt, style: .time).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                        }
                        Text(recap.notes.summary.isEmpty ? "No summary." : recap.notes.summary)
                            .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        if let badge = ScribeRecapNote.badge(for: recap.transcriptionNote) {
                            Text(badge)
                                .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.ember)
                        }
                        if recap.micExcludedDuringCall {
                            Text(ScribeMicCallText.recapLine)
                                .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.ember)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open notes for \(recap.title)")
                .accessibilityHint("Shows the summary, action items, private notes and transcript.")
                Button { scribe.requestDelete(recap.id) } label: {
                    Image(systemName: "trash").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.cloudSecondary)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(recap.title) permanently")
                Button { scribe.dismissRecap(recap.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.cloudSecondary)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(recap.title) from recent meetings")
                .accessibilityHint("Hides it from this list. The saved meeting stays on this Mac until you delete it permanently.")
            }
            if scribe.pendingDeleteID == recap.id {
                ScribeDeleteConfirm(scribe: scribe, id: recap.id)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
}

/// The second step of "Delete permanently": says exactly what is removed, and that it can't be undone.
private struct ScribeDeleteConfirm: View {
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
    let date: Date
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            toolbar
            ScribeInputStatus(scribe: scribe)
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
            ScribeLiveTranscript(scribe: scribe, date: date, reduceMotion: reduceMotion)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Stop and discard on the left, the meter and clock centred.
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
            .frame(minHeight: 28)
        } else {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    ScribeCircleButton(symbol: "stop.fill", label: "Stop recording", hint: "Asks whether to end the meeting.") {
                        scribe.requestEnd()
                    }
                    .accessibilityIdentifier("scribe.stop")
                    ScribeCircleButton(symbol: "trash", label: "Discard recording", hint: "Asks before throwing this meeting away.") {
                        scribe.requestDiscard()
                    }
                }
                Spacer(minLength: 0)
                ScribeRecordingStatus(state: state, elapsed: scribe.elapsed, history: scribe.levelHistory, reduceMotion: reduceMotion)
                Spacer(minLength: 0)
                // Balances the buttons so the meter sits in the middle.
                Color.clear.frame(width: 64, height: 1).accessibilityHidden(true)
            }
            .background { ScribeAccessibilityFocusAnchor(label: "Scribe, listening", focusToken: scribe.focusToken) }
        }
    }
}

/// Which audio is actually being kept: the microphone gate (from the router's own reading) and system audio.
private struct ScribeInputStatus: View {
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
                ScribeLiveLine(
                    segment: segment,
                    shownWords: scribe.visibleWordCount(for: segment, at: date, reduceMotion: reduceMotion)
                )
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
private struct ScribeLiveLine: View {
    let segment: ScribeTranscriptSegment
    let shownWords: Int

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
            Text(ScribeWordText.prefix(segment.text, words: shownWords))
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
private enum ScribeNotesStyle {
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

/// One speaker of the meeting: colour dot, name, talk time and a thin bar for their share of the talking.
private struct ScribeSpeakerRow: View {
    let entry: ScribeSpeakerStats.Entry

    var body: some View {
        let tint = scribeColor(ScribeSpeakerPalette.color(for: entry.speaker))
        let time = ScribeSpeakerStats.format(entry.talkSeconds)
        let percent = Int((entry.share * 100).rounded())
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(entry.speaker.displayName)
                    .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
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
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.speaker.displayName)
        .accessibilityValue("\(time), \(percent) percent of the talking")
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
                    .accessibilityIdentifier("scribe.notes.close")
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
                                ForEach(Array(stats.speakers.enumerated()), id: \.offset) { _, entry in
                                    ScribeSpeakerRow(entry: entry)
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
            Text("Transcript").font(TopBarStyle.label(10, .semibold)).foregroundStyle(ScribeNotesStyle.accent)
                .accessibilityAddTraits(.isHeader)
            if segments.isEmpty {
                Text("No transcript was captured.").font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(segments, id: \.id) { segment in
                            VStack(alignment: .leading, spacing: 1) {
                                // The same colour the speaker had on the live page.
                                HStack(spacing: 4) {
                                    Text(segment.speaker.displayName)
                                        .font(TopBarStyle.label(9, .semibold))
                                        .foregroundStyle(scribeColor(ScribeSpeakerPalette.color(for: segment.speaker)))
                                    Text("· \(RecordlyElapsed.format(segment.start))")
                                        .font(TopBarStyle.label(9).monospacedDigit()).foregroundStyle(Theme.cloudSecondary)
                                }
                                Text(segment.text).font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
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
