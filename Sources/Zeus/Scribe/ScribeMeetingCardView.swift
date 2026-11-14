import SwiftUI
import ZeusCore

// The meeting card, drawn. A pure function of one `ScribeMeetingCard`, the two clock readings and three closures
// (the pointer is reported by the hosting view).
// It stores no meeting, string or phase: every word comes from `ScribeMeetingCardText`, every state from the
// machine. The only motion is one entrance, one in-place crossfade and the countdown ring.

/// What moves, planned from plain numbers so a test can read it against an injected clock.
enum ScribeMeetingCardMotion {
    /// The ring's one linear drain: the share it starts from and the seconds it takes to reach zero.
    struct Sweep: Equatable {
        var from: Double
        var duration: TimeInterval
    }

    /// A state change inside the card is the short crossfade, with or without Reduce Motion.
    static let crossfade = Animation.easeInOut(duration: AlertMotion.reducedFade)

    /// The sweep a ring starts when it appears. Nil with Reduce Motion, and once the deadline has passed.
    static func sweep(deadline: TimeInterval, uptime: TimeInterval, total: TimeInterval, reduceMotion: Bool) -> Sweep? {
        guard !reduceMotion else { return nil }
        let left = deadline - uptime
        guard left.isFinite, left > 0 else { return nil }
        return Sweep(from: ScribeMeetingCardText.ring(deadline: deadline, now: uptime, total: total), duration: left)
    }

    /// The share a redraw shows before any sweep runs: where the sweep starts, or, with Reduce Motion, the
    /// share left at this redraw (the ring steps down once a second instead of sweeping).
    static func drawn(deadline: TimeInterval, uptime: TimeInterval, total: TimeInterval, reduceMotion: Bool) -> Double {
        sweep(deadline: deadline, uptime: uptime, total: total, reduceMotion: reduceMotion)?.from
            ?? ScribeMeetingCardText.ring(deadline: deadline, now: uptime, total: total)
    }

    /// How the card arrives: the alert spring and a 6 pt drop, or only a short fade with Reduce Motion.
    static func entrance(reduceMotion: Bool) -> (animation: Animation, drop: CGFloat) {
        reduceMotion ? (crossfade, 0) : (AlertStyle.stretch, 6)
    }
}

struct ScribeMeetingCardView: View {
    static let width: CGFloat = 340

    let card: ScribeMeetingCard
    /// Wall clock, for "in N min".
    let now: Date
    /// The machine's uptime, for the countdown ring.
    let uptime: TimeInterval
    /// A rendered still has no appearance to wait for.
    var settled = false
    /// Each tap passes `card`, the one drawn here, so no one downstream keeps a copy of what is on screen.
    var onPrimary: (ScribeMeetingCard) -> Void = { _ in }
    var onCancel: (ScribeMeetingCard) -> Void = { _ in }
    var onDismiss: (ScribeMeetingCard) -> Void = { _ in }

    var body: some View {
        if card != .hidden {
            ScribeMeetingCardBody(card: card, now: now, uptime: uptime, settled: settled,
                                  onPrimary: onPrimary, onCancel: onCancel, onDismiss: onDismiss)
        }
    }
}

private struct ScribeMeetingCardBody: View {
    let card: ScribeMeetingCard
    let now: Date
    let uptime: TimeInterval
    let onPrimary: (ScribeMeetingCard) -> Void
    let onCancel: (ScribeMeetingCard) -> Void
    let onDismiss: (ScribeMeetingCard) -> Void
    private let still: Bool
    @State private var landed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(card: ScribeMeetingCard, now: Date, uptime: TimeInterval, settled: Bool,
         onPrimary: @escaping (ScribeMeetingCard) -> Void, onCancel: @escaping (ScribeMeetingCard) -> Void,
         onDismiss: @escaping (ScribeMeetingCard) -> Void) {
        self.card = card
        self.now = now
        self.uptime = uptime
        self.onPrimary = onPrimary
        self.onCancel = onCancel
        self.onDismiss = onDismiss
        still = settled
        _landed = State(initialValue: settled)
    }

    var body: some View {
        let entrance = ScribeMeetingCardMotion.entrance(reduceMotion: reduceMotion)
        row
            .id(card.stateID)
            .transition(.opacity)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: ScribeMeetingCardView.width)
            .alertGlass(radius: 16)
            .preferredColorScheme(.dark)
            // The entrance moves these two only: an animation on the whole card would replace the ring's own
            // linear sweep in the pass where both start.
            .animation(entrance.animation) { $0.opacity(landed ? 1 : 0).offset(y: landed ? 0 : -entrance.drop) }
            .animation(ScribeMeetingCardMotion.crossfade, value: card.stateID)
            .onAppear { landed = true }
            .onChange(of: card.stateID, initial: true) {
                AccessibilityNotification.Announcement(ScribeMeetingCardText.announcement(card, now: now)).post()
            }
    }

    private var row: some View {
        HStack(spacing: 10) {
            Image(systemName: ScribeMeetingCardText.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.cloudPrimary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let meeting = card.meeting {
                    Text(ScribeMeetingCardText.title(meeting))
                        .font(TopBarStyle.label(12.5, .semibold))
                        .foregroundStyle(Theme.cloudPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // One element for the words, "<title>, <status>"; the buttons stay elements of their own.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ScribeMeetingCardText.label(card, now: now))
            controls
        }
        // The height of the row that carries Cancel and its ring, so the card does not shift between states.
        .frame(minHeight: 34)
    }

    /// A word, with a symbol where the state is a result. Never colour alone.
    private var status: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let symbol = card.statusSymbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            }
            Text(ScribeMeetingCardText.status(card, now: now))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(TopBarStyle.label(10, .regular).monospacedDigit())
        .foregroundStyle(Theme.cloudSecondary)
    }

    @ViewBuilder private var controls: some View {
        if card.isStarting { progress }
        if let title = ScribeMeetingCardText.primary(card) {
            Button { onPrimary(card) } label: { ScribeMeetingCardButtonLabel(title: title, prominent: true) }
                .buttonStyle(PressableStyle(reduceMotion: reduceMotion))
                .keyboardShortcut(.defaultAction)
                .ownedJourneyControl("scribe.meetingCard.primary")
        }
        if let title = ScribeMeetingCardText.cancel(card) {
            Button { onCancel(card) } label: { ScribeMeetingCardButtonLabel(title: title, prominent: false) }
                .buttonStyle(PressableStyle(reduceMotion: reduceMotion))
                .keyboardShortcut(.cancelAction)
                .accessibilityValue(ScribeMeetingCardText.accessibilityValue(card) ?? "")
                .ownedJourneyControl("scribe.meetingCard.cancel")
                .overlay { ring }
        }
        if ScribeMeetingCardText.canDismiss(card) {
            Button { onDismiss(card) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.cloudSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle(reduceMotion: reduceMotion))
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(ScribeMeetingCardText.dismiss)
            .ownedJourneyControl("scribe.meetingCard.dismiss")
        }
    }

    /// A small spinner, or three dots with Reduce Motion. The still render has no spinner to draw.
    @ViewBuilder private var progress: some View {
        if reduceMotion || TopBarStyle.isSnapshot {
            Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.cloudSecondary)
                .accessibilityHidden(true)
        } else {
            ProgressView().controlSize(.small).accessibilityHidden(true)
        }
    }

    /// Only the countdown has a ring. Keyed on the deadline so the per-second redraw never restarts it.
    @ViewBuilder private var ring: some View {
        if case .countdown(_, _, let deadline, let total) = card {
            ScribeMeetingCardRing(deadline: deadline, uptime: uptime, total: total, reduceMotion: reduceMotion, still: still)
                .id(deadline)
                // Around the button, outside its frame, so Cancel sits where Record sits.
                .padding(-4)
        }
    }
}

/// The thin ring that drains over the countdown. One linear animation, started with the time left.
struct ScribeMeetingCardRing: View {
    let deadline: TimeInterval
    let uptime: TimeInterval
    let total: TimeInterval
    let reduceMotion: Bool
    /// A rendered still shows the share as given and never starts the sweep.
    let still: Bool
    @State private var share: Double

    init(deadline: TimeInterval, uptime: TimeInterval, total: TimeInterval, reduceMotion: Bool, still: Bool) {
        self.still = still
        self.deadline = deadline
        self.uptime = uptime
        self.total = total
        self.reduceMotion = reduceMotion
        _share = State(initialValue: ScribeMeetingCardMotion.drawn(deadline: deadline, uptime: uptime, total: total,
                                                                   reduceMotion: reduceMotion))
    }

    var body: some View {
        ZStack {
            Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1.5)
            Capsule()
                .trim(from: 0, to: reduceMotion ? stepped : share)
                .stroke(Theme.cloudPrimary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !still, let plan = ScribeMeetingCardMotion.sweep(deadline: deadline, uptime: uptime, total: total,
                                                                   reduceMotion: reduceMotion) else { return }
            withAnimation(.linear(duration: plan.duration)) { share = 0 }
        }
    }

    private var stepped: Double {
        ScribeMeetingCardMotion.drawn(deadline: deadline, uptime: uptime, total: total, reduceMotion: true)
    }
}

private struct ScribeMeetingCardButtonLabel: View {
    let title: String
    let prominent: Bool

    var body: some View {
        Text(title)
            .font(TopBarStyle.label(11, .semibold))
            .foregroundStyle(Theme.cloudPrimary)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(prominent ? Theme.accent.opacity(0.5) : Color.white.opacity(0.1)))
    }
}

private extension ScribeMeetingCard {
    /// Changes when the card becomes another state, not when its seconds or minutes tick.
    var stateID: String {
        switch self {
        case .hidden: return "hidden"
        case .offer(let meeting, let blocked): return "offer.\(meeting.key).\(String(describing: blocked))"
        case .countdown(let meeting, _, let deadline, _): return "countdown.\(meeting.key).\(deadline)"
        case .waiting(let meeting): return "waiting.\(meeting.key)"
        case .starting(let meeting, let cancellable): return "starting.\(meeting.key).\(cancellable)"
        case .recording(let meeting): return "recording.\(meeting.key)"
        case .failed(let meeting, let failure): return "failed.\(meeting.key).\(failure)"
        case .next(let meeting): return "next.\(meeting.key)"
        }
    }

    var isStarting: Bool {
        if case .starting = self { return true }
        return false
    }

    var statusSymbol: String? {
        switch self {
        case .failed: return "exclamationmark.triangle.fill"
        case .recording: return "waveform"
        default: return nil
        }
    }
}

// MARK: Still fixtures

/// Every card state with synthetic meetings, for `Zeus --snapshots`. No service, clock or panel is involved.
enum ScribeMeetingCardFixture {
    struct Entry {
        let name: String
        let card: ScribeMeetingCard
        let uptime: TimeInterval
    }

    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let size = CGSize(width: 380, height: 104)
    private static let uptime: TimeInterval = 100

    private static func meeting(_ title: String = "Weekly sync", startsIn: TimeInterval = 120) -> ScribeMeeting {
        let slot = ScribeCalendarSlot(id: "fixture-\(title)", title: title, start: now.addingTimeInterval(startsIn),
                                      hasCallLink: true)
        return ScribeMeeting(key: slot.id, title: title, callApp: .other("Synthetic"), slot: slot)
    }

    private static func countdown(_ seconds: Int) -> ScribeMeetingCard {
        .countdown(meeting(startsIn: 0), seconds: seconds, deadline: uptime + Double(seconds), total: 5)
    }

    static let entries: [Entry] = {
        let long = meeting("Quarterly planning review with the whole regional leadership team")
        let rows: [(String, ScribeMeetingCard)] = [
            ("offer", .offer(meeting(), blocked: nil)),
            ("offer-long-title", .offer(long, blocked: nil)),
            ("offer-now", .offer(meeting(startsIn: 0), blocked: nil)),
            ("offer-blocked-microphone-not-asked", .offer(meeting(), blocked: .microphoneNotAsked)),
            ("offer-blocked-microphone-denied", .offer(meeting(), blocked: .microphoneDenied)),
            ("offer-blocked-first-recording", .offer(meeting(), blocked: .firstRecordingOwed)),
            ("countdown-5", countdown(5)),
            ("countdown-3", countdown(3)),
            ("countdown-1", countdown(1)),
            ("waiting", .waiting(meeting(startsIn: 0))),
            ("starting-cancellable", .starting(meeting(startsIn: 0), cancellable: true)),
            ("starting", .starting(meeting(startsIn: 0), cancellable: false)),
            ("recording", .recording(meeting(startsIn: 0))),
            ("failed-microphone-off", .failed(meeting(startsIn: 0), .microphoneOff)),
            ("failed-still-saving", .failed(meeting(startsIn: 0), .stillSaving)),
            ("failed-capture", .failed(meeting(startsIn: 0), .captureFailed("No input device is available"))),
            ("failed-no-response", .failed(meeting(startsIn: 0), .noResponse)),
            ("next", .next(meeting("Design review", startsIn: 60))),
            ("next-now", .next(meeting("Design review", startsIn: 0))),
        ]
        return rows.map { Entry(name: "meeting-card-\($0.0)", card: $0.1, uptime: uptime) }
    }()

    /// The card on the backdrop the other card fixtures use, drawn as it rests.
    static func view(_ entry: Entry) -> some View {
        ScribeMeetingCardView(card: entry.card, now: now, uptime: entry.uptime, settled: true)
            .padding(20)
            .background(Color(hex: 0x1B2030))
    }
}
