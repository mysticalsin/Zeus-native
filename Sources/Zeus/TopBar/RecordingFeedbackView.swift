import SwiftUI
import ZeusCore

/// One renderer for both real producers, including their post-capture work. Controls and labels
/// stay readable while the decoration moves; accessibility preferences remove motion/material.
struct RecordingFeedbackView: View {
    let snapshot: RecordingFeedback.Snapshot
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || snapshot.phase == .failed)) { context in
            RecordingFeedbackFrameView(snapshot: snapshot, date: context.date, reduceMotion: reduceMotion,
                                       reduceTransparency: reduceTransparency, open: open)
        }
    }
}

/// The production frame, with its clock and accessibility preferences passed explicitly so
/// native tests can render the real motion over time without starting capture or a TimelineView.
struct RecordingFeedbackFrameView: View {
    let snapshot: RecordingFeedback.Snapshot
    let date: Date
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let open: () -> Void

    var body: some View {
        let frame = RecordingFeedback.frame(snapshot, at: date.timeIntervalSinceReferenceDate,
                                             reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
        if frame.visible {
            Button(action: open) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                        .opacity(0.35 + 0.65 * frame.reveal)
                    Text(snapshot.label)
                        .font(TopBarStyle.label(10.5, .semibold))
                        .foregroundStyle(Theme.cloudPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background {
                    Capsule().fill(reduceTransparency ? Color.black : Color.white.opacity(0.08 + frame.frost))
                        .overlay {
                            Capsule().strokeBorder(tint.opacity(frame.glow), lineWidth: 1)
                        }
                        .overlay {
                            if !reduceMotion {
                                GeometryReader { geometry in
                                    Capsule().fill(tint.opacity(frame.frost))
                                        .frame(width: 28)
                                        .offset(x: (geometry.size.width + 28) * frame.sweep - 28)
                                }
                                .clipShape(Capsule())
                            }
                        }
                        .shadow(color: tint.opacity(frame.glow * 0.45), radius: 6)
                }
            }
            .buttonStyle(PressableStyle(reduceMotion: reduceMotion))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(snapshot.label)
            .accessibilityHint("Opens \(snapshot.producer == .meetings ? "Meetings" : "Recordly").")
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
