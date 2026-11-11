import SwiftUI
import ZeusCore

/// One renderer for both real producers, including their post-capture work. Controls and labels
/// stay readable while the decoration moves; accessibility preferences remove motion/material.
struct RecordingFeedbackView: View {
    let snapshot: RecordingFeedback.Snapshot
    let open: () -> Void
    @StateObject private var status: RecordingFeedbackStatusDriver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(snapshot: RecordingFeedback.Snapshot, open: @escaping () -> Void) {
        self.snapshot = snapshot
        self.open = open
        _status = StateObject(wrappedValue: RecordingFeedbackStatusDriver(snapshot: snapshot))
    }

    var body: some View {
        DisplaySynchronizedView(paused: reduceMotion || ((snapshot.phase == .failed || snapshot.phase == .completed) && !status.isAnimating),
                                preferredFramesPerSecond: 240) { context in
            let sameSession = status.transition.target.producer == snapshot.producer && status.transition.target.sessionKey == snapshot.sessionKey
            let label = sameSession
                ? status.transition.frame(at: context.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion)
                : .settled(snapshot.label)
            RecordingFeedbackFrameView(snapshot: snapshot, date: context.date, reduceMotion: reduceMotion,
                                       reduceTransparency: reduceTransparency, status: label,
                                       beamElapsed: sameSession ? status.beamTimeline.elapsed(at: context.date.timeIntervalSinceReferenceDate) : nil,
                                       open: open)
        }
        .onChange(of: snapshot) { status.update(snapshot, reduceMotion: reduceMotion) }
        .onChange(of: reduceMotion) { status.update(snapshot, reduceMotion: reduceMotion) }
        .onAppear { status.update(snapshot, reduceMotion: reduceMotion) }
        .onDisappear { status.stop() }
    }
}

@MainActor
final class RecordingFeedbackStatusDriver: ObservableObject {
    @Published private(set) var transition: RecordingFeedback.StatusTransition
    @Published private(set) var beamTimeline: RecordingFeedback.BeamTimeline
    @Published private(set) var isAnimating = false
    private var settling: Task<Void, Never>?

    init(snapshot: RecordingFeedback.Snapshot) {
        transition = .init(snapshot)
        beamTimeline = .init(snapshot)
    }

    func update(_ snapshot: RecordingFeedback.Snapshot, reduceMotion: Bool) {
        settling?.cancel()
        let now = Date.timeIntervalSinceReferenceDate
        beamTimeline.update(snapshot)
        transition.update(snapshot, at: now, reduceMotion: reduceMotion)
        let remaining = RecordingFeedback.transientMotionRemaining(snapshot, status: transition, at: now, reduceMotion: reduceMotion)
        isAnimating = remaining > 0
        guard isAnimating else { return }
        settling = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.transition.settle()
            self.isAnimating = false
        }
    }

    func stop() {
        settling?.cancel()
        settling = nil
        transition.settle()
        isAnimating = false
    }
}

/// The production frame, with its clock and accessibility preferences passed explicitly so
/// native tests can render the real motion over time without starting capture or a view clock.
struct RecordingFeedbackFrameView: View {
    let snapshot: RecordingFeedback.Snapshot
    let date: Date
    let reduceMotion: Bool
    let reduceTransparency: Bool
    var status: RecordingFeedback.StatusFrame? = nil
    var beamElapsed: TimeInterval? = nil
    let open: () -> Void

    var body: some View {
        let frame = RecordingFeedback.frame(snapshot, at: date.timeIntervalSinceReferenceDate,
                                             reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
        let label = reduceMotion ? RecordingFeedback.StatusFrame.settled(snapshot.label) : status ?? .settled(snapshot.label)
        let beamTime = reduceMotion ? 0 : beamElapsed ?? frame.elapsed
        if frame.visible {
            Button(action: open) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                        .opacity(frame.reveal)
                        .blur(radius: frame.blur)
                    Text(label.text)
                        .font(TopBarStyle.label(10.5, .semibold))
                        .foregroundStyle(Theme.cloudPrimary)
                        .lineLimit(1)
                        .opacity(label.opacity)
                        .offset(y: label.offsetY)
                        .blur(radius: label.blur)
                }
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background {
                    Capsule().fill(reduceTransparency ? Color.black : Color.white.opacity(0.08))
                        .overlay {
                            if frame.beamOpacity > 0 {
                                AssistantBeamView(
                                    frame: AssistantBeam.frame(elapsed: beamTime, level: 0,
                                                               processing: snapshot.phase != .failed,
                                                               processingElapsed: beamTime, reduceMotion: reduceMotion),
                                    reduceTransparency: reduceTransparency, cornerRadius: 12
                                )
                                .opacity(frame.beamOpacity)
                            }
                        }
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                }
            }
            .buttonStyle(RecordingFeedbackPressStyle(reduceMotion: reduceMotion))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(snapshot.label)
            .accessibilityHint("Opens \(snapshot.producer == .meetings ? "Meetings" : "Record").")
            .accessibilityIdentifier("recording.feedback.\(snapshot.producer.rawValue)")
            .help(snapshot.label)
        }
    }

    private var tint: Color { snapshot.phase == .failed ? Theme.ember : Theme.glow }
    private var symbol: String {
        switch snapshot.phase {
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .starting: "record.circle"
        case .finishing, .writing: "text.badge.checkmark"
        case .exporting: "square.and.arrow.up"
        }
    }
}

private struct RecordingFeedbackPressStyle: ButtonStyle {
    let reduceMotion: Bool
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(enabled && configuration.isPressed && !reduceMotion ? RecordingFeedback.Motion.pressedScale : 1)
            .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: RecordingFeedback.Motion.pressDuration),
                       value: configuration.isPressed)
    }
}

extension ScribeController {
    func topBarFeedback(at date: Date = Date()) -> RecordingFeedback.Snapshot? {
        guard let id = phase.sessionID else { return nil }
        let key = id.rawValue.uuidString
        let began = date.timeIntervalSinceReferenceDate - stageElapsed(at: date)
        switch phase {
        case .starting:
            return .init(producer: .meetings, phase: .starting, sessionKey: key, beganAt: began, label: "Connecting to meeting")
        case .processing:
            return .init(producer: .meetings, phase: completionSaveIssue == nil ? .writing : .failed,
                         sessionKey: key, beganAt: began,
                         label: completionSaveIssue == nil ? "Writing meeting notes" : "Meeting needs saving")
        case .complete:
            guard completedNoticeID == id else { return nil }
            return .init(producer: .meetings, phase: .completed, sessionKey: key, beganAt: began, label: "Meeting notes saved")
        case .failed:
            return .init(producer: .meetings, phase: .failed, sessionKey: key, beganAt: began, label: "Meeting needs attention")
        case .idle, .recording, .ending: return nil
        }
    }
}
