import CoreGraphics
import Foundation

// The meeting card as a value. The machine computes one `ScribeMeetingCard`; the view draws it and nothing
// else. Every word on the card comes from `ScribeMeetingCardText`. Pure: no AppKit, no clock, no state.

/// Why a tap, or an automatic start, did not end in a recording.
public enum ScribeStartFailure: Equatable, Sendable {
    case microphoneOff
    case stillSaving
    /// Scribe's own reason for a capture that did not begin.
    case captureFailed(String)
    case noResponse
}

/// What is missing for an automatic start, so the card can ask instead.
public enum ScribeAutoStartBlock: CaseIterable, Equatable, Sendable {
    case notChosen
    case noOptIn
    case microphoneNotAsked
    case microphoneDenied
    case firstRecordingOwed
}

/// Everything the card can show. `hidden` is the only case with nothing to draw.
public enum ScribeMeetingCard: Equatable, Sendable {
    case hidden
    case offer(ScribeMeeting, blocked: ScribeAutoStartBlock?)
    /// `deadline` and `total` are on the machine's clock; `seconds` is what was left when the card was made.
    case countdown(ScribeMeeting, seconds: Int, deadline: TimeInterval, total: TimeInterval)
    case waiting(ScribeMeeting)
    case starting(ScribeMeeting, cancellable: Bool)
    case recording(ScribeMeeting)
    case failed(ScribeMeeting, ScribeStartFailure)
    case next(ScribeMeeting)

    public var meeting: ScribeMeeting? {
        switch self {
        case .hidden: return nil
        case .offer(let meeting, _), .countdown(let meeting, _, _, _), .waiting(let meeting),
             .starting(let meeting, _), .recording(let meeting), .failed(let meeting, _), .next(let meeting):
            return meeting
        }
    }
}

/// The two clock readings a card is read against: wall time for "in 2 min", uptime for the countdown.
public struct ScribeCardClock: Equatable, Sendable {
    public var date: Date
    public var uptime: TimeInterval

    public init(date: Date, uptime: TimeInterval) {
        self.date = date
        self.uptime = uptime
    }
}

public enum ScribeMeetingCardText {
    /// One generic symbol for every card.
    public static let symbol = "video.fill"
    public static let dismiss = "Dismiss"

    // MARK: Words

    /// The meeting title. A call with no calendar meeting behind it is just "Call".
    public static func title(_ meeting: ScribeMeeting) -> String {
        guard meeting.slot != nil else { return "Call" }
        let title = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Meeting" : title
    }

    /// "in N min", rounded up, before the start; "now" from the start.
    public static func time(startsAt: Date, now: Date) -> String {
        let until = startsAt.timeIntervalSince(now)
        guard until > 0 else { return "now" }
        return "in \(max(1, Int((until / 60).rounded(.up)))) min"
    }

    public static func status(_ card: ScribeMeetingCard, now: ScribeCardClock) -> String {
        switch card {
        case .hidden:
            return ""
        case .offer(let meeting, let blocked):
            return blocked.flatMap { reason($0) } ?? time(of: meeting, now: now)
        case .next(let meeting):
            return time(of: meeting, now: now)
        case .countdown(_, let seconds, _, _):
            return "Recording starts in \(seconds)"
        case .waiting:
            return "Starts once your last meeting is saved"
        case .starting:
            return "Starting"
        case .recording:
            return "Recording"
        case .failed(_, let failure):
            return reason(failure)
        }
    }

    public static func reason(_ failure: ScribeStartFailure) -> String {
        switch failure {
        case .microphoneOff:
            return "Microphone is off for Zeus"
        case .stillSaving:
            return "Still saving your last meeting"
        case .captureFailed(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Couldn't start" : trimmed
        case .noResponse:
            return "Didn't start"
        }
    }

    /// Nil when the person has nothing to fix: the card then shows the time as usual.
    public static func reason(_ block: ScribeAutoStartBlock) -> String? {
        switch block {
        case .notChosen, .noOptIn: return nil
        case .microphoneNotAsked: return "Microphone not allowed yet"
        case .microphoneDenied: return "Microphone is off for Zeus"
        case .firstRecordingOwed: return "Automatic start needs one recording first"
        }
    }

    // MARK: Controls

    public static func primary(_ card: ScribeMeetingCard) -> String? {
        switch card {
        case .offer: return "Record"
        case .failed(_, .microphoneOff): return "Allow"
        case .failed: return "Try again"
        case .next: return "Switch"
        case .hidden, .countdown, .waiting, .starting, .recording: return nil
        }
    }

    public static func cancel(_ card: ScribeMeetingCard) -> String? {
        switch card {
        case .countdown, .waiting, .starting(_, cancellable: true): return "Cancel"
        default: return nil
        }
    }

    public static func canDismiss(_ card: ScribeMeetingCard) -> Bool {
        switch card {
        case .offer, .failed, .next: return true
        default: return false
        }
    }

    // MARK: Countdown arithmetic

    /// Whole seconds left, counting the one in progress: 5 from the start until one second has passed.
    public static func seconds(deadline: TimeInterval, now: TimeInterval) -> Int {
        let left = deadline - now
        guard left.isFinite, left > 0 else { return 0 }
        return Int(left.rounded(.up))
    }

    /// The share of the countdown left, from 1 down to 0.
    public static func ring(deadline: TimeInterval, now: TimeInterval, total: TimeInterval) -> Double {
        guard total > 0, total.isFinite else { return 0 }
        let share = (deadline - now) / total
        guard share.isFinite else { return 0 }
        return min(1, max(0, share))
    }

    // MARK: Accessibility

    /// "<title>, <status>", empty for a hidden card.
    public static func label(_ card: ScribeMeetingCard, now: ScribeCardClock) -> String {
        guard let meeting = card.meeting else { return "" }
        return "\(title(meeting)), \(status(card, now: now))"
    }

    /// Spoken once when the card changes state. The countdown is stated at its full length, so the text does
    /// not change while it counts down.
    public static func announcement(_ card: ScribeMeetingCard, now: ScribeCardClock) -> String {
        guard case .countdown(let meeting, _, _, let total) = card else { return label(card, now: now) }
        return "\(title(meeting)), Recording starts in \(Int(total.rounded()))"
    }

    /// What Cancel reports as its value: the seconds left on a countdown, nothing otherwise.
    public static func accessibilityValue(_ card: ScribeMeetingCard) -> String? {
        guard case .countdown(_, let seconds, _, _) = card else { return nil }
        return String(seconds)
    }

    private static func time(of meeting: ScribeMeeting, now: ScribeCardClock) -> String {
        guard let slot = meeting.slot else { return "now" }
        return time(startsAt: slot.start, now: now.date)
    }
}

/// Where the card sits on a screen.
public enum ScribeMeetingCardPlacement {
    /// The top right corner of `visibleFrame`, in AppKit's bottom-left coordinates, kept inside the frame.
    public static func origin(size: CGSize, visibleFrame: CGRect, margin: CGFloat) -> CGPoint {
        CGPoint(x: max(visibleFrame.minX, visibleFrame.maxX - size.width - margin),
                y: max(visibleFrame.minY, visibleFrame.maxY - size.height - margin))
    }
}
