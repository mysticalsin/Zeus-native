import SwiftUI
import ZeusCore

// Pieces of the recording page: the "Now speaking" pill and the level ribbon in the speaker's colour.
// Both read what the controller already publishes (newest transcript line, 24-value level history), so
// nothing here listens to audio or runs a clock.

/// A coloured disc with initials: the same speaker colour the transcript chips use.
struct ScribeSpeakerDisc: View {
    let initials: String
    let tint: Color
    var size: CGFloat = 18

    var body: some View {
        Text(initials)
            .font(TopBarStyle.label(size * 0.45, .bold)).foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.22)))
            .overlay(Circle().strokeBorder(tint.opacity(0.7), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// "Now speaking: Marie Dubois". While no name is known it says "Naming…" with a dotted disc, never "Speaker 2".
/// The name cross-fades in 150 ms (no fade under Reduce Motion). VoiceOver hears a polite announcement on a change,
/// at most once every three seconds.
struct ScribeNowSpeakingPill: View {
    let current: ScribeNowSpeaking?
    let reduceMotion: Bool
    @State private var lastAnnounced = Date.distantPast

    var body: some View {
        HStack(spacing: 6) {
            inner
                .id(current?.name ?? "")
                .transition(.opacity)
        }
        .padding(.leading, 3).padding(.trailing, 10)
        .frame(height: 24)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: current?.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(current?.spoken ?? "Listening, nobody has spoken yet")
        .onChange(of: current?.spoken) { _, spoken in announce(spoken) }
    }

    @ViewBuilder
    private var inner: some View {
        if let current {
            HStack(spacing: 6) {
                ScribeSpeakerDisc(initials: current.initials, tint: tint(current))
                Text("Now speaking")
                    .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudQuiet)
                Text(current.name)
                    .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.cloudSecondary)
                    .frame(width: 18, height: 18)
                Text("Listening\u{2026}")
                    .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudSecondary)
            }
        }
    }

    private func tint(_ current: ScribeNowSpeaking) -> Color {
        scribeColor(ScribeSpeakerPalette.color(for: current.speaker))
    }

    private func announce(_ spoken: String?) {
        guard let spoken, Date().timeIntervalSince(lastAnnounced) >= 3 else { return }
        lastAnnounced = Date()
        AccessibilityNotification.Announcement(spoken).post()
    }
}

/// How loud the meeting is, the newest of 24 values on the right, drawn in the current speaker's colour.
struct ScribeLevelRibbon: View {
    let history: [Double]
    let tint: Color
    let reduceMotion: Bool

    private static let count = 24

    private var levels: [Double] {
        let tail = Array(history.suffix(Self.count))
        return Array(repeating: 0, count: max(0, Self.count - tail.count)) + tail
    }

    var body: some View {
        let values = levels
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, raw in
                let level = min(1, max(0, raw.isFinite ? raw : 0))
                Capsule()
                    .fill(tint.opacity(0.3 + 0.7 * level))
                    .frame(maxWidth: .infinity)
                    .frame(height: 3 + 15 * CGFloat(level))
            }
        }
        .frame(height: 20)
        .animation(reduceMotion ? nil : .linear(duration: 0.06), value: values)
        .accessibilityHidden(true)
    }
}

/// The row under the toolbar: who is speaking, how loud, and which audio is being kept.
struct ScribeLiveStatusRow: View {
    let scribe: ScribeController
    let reduceMotion: Bool

    var body: some View {
        let current = ScribeNowSpeaking.current(in: scribe.liveSegments(limit: 24))
        let tint = current.map { scribeColor(ScribeSpeakerPalette.color(for: $0.speaker)) } ?? Theme.cloudSecondary
        HStack(spacing: 10) {
            ScribeNowSpeakingPill(current: current, reduceMotion: reduceMotion)
            ScribeLevelRibbon(history: scribe.levelHistory, tint: tint, reduceMotion: reduceMotion)
                .frame(maxWidth: 240)
            Spacer(minLength: 0)
            ScribeInputStatus(scribe: scribe)
        }
    }
}
