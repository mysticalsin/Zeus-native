import SwiftUI
import ZeusCore

/// Recording wings for ClosedWings: a breathing dot and the elapsed clock with Stop. Driven only by
/// the producer's elapsed value (no timer of its own); Reduce Motion keeps the dot steady.
enum RecordingActivityWings {
    struct Leading: View {
        let input: RecordingMotion.Input
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pulse = RecordingMotion.present(input, reduceMotion: reduceMotion).pulse
            let frame = RecordingMotion.frame(pulse, at: input.elapsed)
            Circle().fill(TopBarStyle.rec).frame(width: 7, height: 7)
                .scaleEffect(CGFloat(frame.scale))
                .opacity(frame.opacity)
                .shadow(color: frame.haloRadius > 0 ? TopBarStyle.rec.opacity(0.8) : .clear, radius: CGFloat(frame.haloRadius))
                .animation(pulse == .steady ? nil : .linear(duration: RecordingMotion.sampleInterval), value: frame)
                .accessibilityHidden(true)
        }
    }

    struct Trailing: View {
        let input: RecordingMotion.Input
        let elapsedText: String?
        let onStop: () -> Void
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let presentation = RecordingMotion.present(input, reduceMotion: reduceMotion)
            HStack(spacing: 6) {
                if let elapsedText {
                    Text(elapsedText)
                        .font(TopBarStyle.label(11, .semibold).monospacedDigit())
                        .foregroundStyle(TopBarStyle.rec)
                        .accessibilityLabel(presentation.accessibility.label)
                        .accessibilityValue(presentation.accessibility.value)
                }
                if presentation.stop == .available {
                    NotchActionButton(title: "Stop", tint: TopBarStyle.rec, action: onStop)
                        .accessibilityLabel(presentation.accessibility.stopLabel)
                        .accessibilityHint(presentation.accessibility.stopHint)
                }
            }
        }
    }
}
