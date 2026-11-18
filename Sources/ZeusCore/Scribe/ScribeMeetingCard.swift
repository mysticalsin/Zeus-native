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


/// The card's measurements, in points. One place, so the view, the panel and the tests read the same numbers.
/// The compact card of 2026-11-18 (docs/MEETING-START-PLAN.md, MS5).
public enum ScribeMeetingCardMetrics {
    /// The longest fixed detail wording that fits beside the widest action capsule ("Join in Zoom" with its menu)
    /// at the detail size, measured from the rendered card.
    public static let detailMaxCharacters = 15
    /// The glass slab.
    public static let width: CGFloat = 340
    public static let height: CGFloat = 96
    public static let cornerRadius: CGFloat = 22
    public static let rim: CGFloat = 1.25
    /// Padding inside the slab.
    public static let padding: CGFloat = 12
    /// Room the window adds on every side so the shadow is not cut off.
    public static let shadowRoom: CGFloat = 16
    /// The slab's soft shadow.
    public static let shadowRadius: CGFloat = 12
    public static let shadowY: CGFloat = 6
    /// The slab's distance from the top and right edges of the visible frame.
    public static let margin: CGFloat = 24

    /// The left column: the orb with its ring, then the app tiles. A narrow fixed column, no split and no divider.
    public static let leftColumnWidth: CGFloat = 64
    public static let orb: CGFloat = 40
    public static let orbSymbolSize: CGFloat = 18
    public static let ringInset: CGFloat = 4
    public static var ringDiameter: CGFloat { orb + 2 * ringInset }
    public static let ringWidth: CGFloat = 2
    public static let tile: CGFloat = 16
    public static let tileSpacing: CGFloat = 4
    public static let tileSymbolSize: CGFloat = 9
    public static let maxApps = 3
    /// The gap between the ring and the tile row.
    public static let orbTileGap: CGFloat = 6
    public static var orbGroupHeight: CGFloat { ringDiameter + orbTileGap + tile }

    /// The right column, three rows: the title (with the close button), the status, and the bottom row that holds
    /// the third line and the action capsule.
    public static let titleSize: CGFloat = 15
    public static let titleRowHeight: CGFloat = 20
    public static let closeSize: CGFloat = 20
    public static let closeSymbolSize: CGFloat = 9
    public static let pillTextSize: CGFloat = 10
    public static let pillHeight: CGFloat = 16
    public static let timeSize: CGFloat = 12
    public static let statusRowHeight: CGFloat = 16
    public static let detailSize: CGFloat = 11
    public static let capsuleHeight: CGFloat = 26
    public static let capsuleLabelSize: CGFloat = 12
    public static let capsuleSymbolSize: CGFloat = 11
    /// The gaps between the rows. The second is a minimum: the bottom row sits at the bottom of the slab.
    public static let titleGap: CGFloat = 3
    public static let bottomGap: CGFloat = 4
    /// The three rows and their gaps, which must fit inside the padding.
    public static var contentHeight: CGFloat {
        titleRowHeight + titleGap + statusRowHeight + bottomGap + capsuleHeight
    }

    /// The window around the slab.
    public static var windowSize: CGSize {
        CGSize(width: width + 2 * shadowRoom, height: height + 2 * shadowRoom)
    }

    /// The orb's centre in slab coordinates, from the top left. The ring is centred on it, so a reader of
    /// pixels knows where to look. The orb and the tile row are one group centred in the column.
    public static var orbCenter: CGPoint {
        let top = padding + (height - 2 * padding - orbGroupHeight) / 2
        return CGPoint(x: padding + leftColumnWidth / 2, y: top + ringDiameter / 2)
    }
}

/// What the status pill's dot says about the state.
public enum ScribeMeetingCardTone: Equatable, Sendable {
    case soon
    case recording
    case problem
}

/// The controls a card can draw.
public enum ScribeMeetingCardControl: Equatable, Sendable {
    case primary
    case apps
    case cancel
    case dismiss
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

    public static func status(_ card: ScribeMeetingCard, now: Date) -> String {
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
            return "Didn't start. Try again."
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


    // MARK: The redrawn card

    /// The orb's symbol; `symbol` is the call symbol on the Join button.
    public static let orbSymbol = "calendar"
    public static let cancelSymbol = "xmark"

    /// The status pill's short phrase. Empty for a hidden card.
    /// With `now`, a meeting that has already begun reads "Meeting started" instead of "Starting soon", so the
    /// pill never contradicts a "Now" time beside it.
    public static func pill(_ card: ScribeMeetingCard, now: Date? = nil) -> String {
        switch card {
        case .hidden: return ""
        case .offer(let meeting, _), .next(let meeting):
            if let now, let start = meeting.slot?.start, start <= now { return "Meeting started" }
            return "Starting soon"
        case .countdown(_, let seconds, _, _): return "Recording in \(seconds)"
        case .waiting: return "Waiting to record"
        case .starting: return "Starting"
        case .recording: return "Recording"
        case .failed: return "Not recorded"
        }
    }

    public static func tone(_ card: ScribeMeetingCard) -> ScribeMeetingCardTone {
        switch card {
        case .recording: return .recording
        case .failed: return .problem
        default: return .soon
        }
    }

    /// The line that holds a reason or a wait. Nil when there is nothing to say; the card then shows the
    /// participants, if the calendar gave any.
    /// Short wording: the line sits beside the action capsule (`detailMaxCharacters`); the status text and the
    /// spoken label keep the full sentence.
    public static func detail(_ card: ScribeMeetingCard) -> String? {
        switch card {
        case .offer(_, let blocked):
            switch blocked {
            case .microphoneNotAsked: return "Mic not allowed"
            case .microphoneDenied: return "Mic is off"
            case .firstRecordingOwed: return "Record first"
            case .notChosen, .noOptIn, nil: return nil
            }
        case .failed(_, let failure):
            switch failure {
            case .microphoneOff: return "Mic is off"
            case .stillSaving: return "Still saving"
            case .noResponse: return "Didn't start"
            case .captureFailed: return reason(failure)
            }
        case .waiting: return "After last save"
        default: return nil
        }
    }

    /// "In N min" or "Now", the status time in capitals for the time line.
    public static func relative(startsAt: Date, now: Date) -> String {
        let phrase = time(startsAt: startsAt, now: now)
        return phrase.prefix(1).uppercased() + phrase.dropFirst()
    }

    public struct TimeLine: Equatable, Sendable {
        /// "9:45 AM to 10:30 AM", or only the start when the event has no end. Nil for a call with no meeting.
        public var range: String?
        public var relative: String
    }

    public static func timeLine(_ meeting: ScribeMeeting, now: Date, locale: Locale = .current,
                                timeZone: TimeZone = .current) -> TimeLine {
        guard let slot = meeting.slot else { return TimeLine(range: nil, relative: "Now") }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let start = formatter.string(from: slot.start)
        let range = slot.end.map { "\(start) to \(formatter.string(from: $0))" } ?? start
        return TimeLine(range: range, relative: relative(startsAt: slot.start, now: now))
    }

    /// "N participants" when the calendar names guests: the named guests and the owner. Nil otherwise.
    public static func participants(_ meeting: ScribeMeeting) -> String? {
        guard let names = meeting.slot?.attendeeNames, !names.isEmpty else { return nil }
        return "\(names.count + 1) participants"
    }

    public static func join(_ appName: String) -> String { "Join in \(appName)" }

    /// Join replaces the offer's own action only before the start, with a link Zeus already holds and an app
    /// to open it in. Every other state keeps its own action.
    public static func canJoin(_ card: ScribeMeetingCard, apps: [ScribeJoinApp]) -> Bool {
        guard case .offer(let meeting, _) = card, meeting.slot?.callLink != nil else { return false }
        return !apps.isEmpty
    }

    public static func primarySymbol(_ card: ScribeMeetingCard) -> String? {
        switch card {
        case .offer: return "record.circle"
        case .failed(_, .microphoneOff): return "mic.fill"
        case .failed: return "arrow.clockwise"
        case .next: return "arrow.triangle.swap"
        case .hidden, .countdown, .waiting, .starting, .recording: return nil
        }
    }

    /// The controls drawn whether or not the pointer is over the card.
    public static func controlsAtRest(_ card: ScribeMeetingCard, canJoin: Bool) -> [ScribeMeetingCardControl] {
        guard card != .hidden else { return [] }
        var controls: [ScribeMeetingCardControl] = []
        if canJoin {
            controls += [.primary, .apps]
        } else if primary(card) != nil {
            controls.append(.primary)
        }
        if cancel(card) != nil { controls.append(.cancel) }
        return controls
    }

    /// The controls that appear when the pointer is over the card: the close button, where the card can be
    /// dismissed. It stays reachable for VoiceOver and the keyboard at rest.
    public static func revealedOnHover(_ card: ScribeMeetingCard) -> [ScribeMeetingCardControl] {
        canDismiss(card) ? [.dismiss] : []
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
    public static func label(_ card: ScribeMeetingCard, now: Date) -> String {
        guard let meeting = card.meeting else { return "" }
        return "\(title(meeting)), \(status(card, now: now))"
    }

    /// Spoken once when the card changes state. The countdown is stated at its full length, so the text does
    /// not change while it counts down.
    public static func announcement(_ card: ScribeMeetingCard, now: Date) -> String {
        guard case .countdown(let meeting, _, _, let total) = card else { return label(card, now: now) }
        return "\(title(meeting)), Recording starts in \(Int(total.rounded()))"
    }

    /// What Cancel reports as its value: the seconds left on a countdown, nothing otherwise.
    public static func accessibilityValue(_ card: ScribeMeetingCard) -> String? {
        guard case .countdown(_, let seconds, _, _) = card else { return nil }
        return String(seconds)
    }

    private static func time(of meeting: ScribeMeeting, now: Date) -> String {
        guard let slot = meeting.slot else { return "now" }
        return time(startsAt: slot.start, now: now)
    }
}

/// Where the card sits on a screen.
public enum ScribeMeetingCardPlacement {
    /// The top right corner of `visibleFrame`, in AppKit's bottom-left coordinates, kept inside the frame.
    public static func origin(size: CGSize, visibleFrame: CGRect, margin: CGFloat) -> CGPoint {
        CGPoint(x: max(visibleFrame.minX, visibleFrame.maxX - size.width - margin),
                y: max(visibleFrame.minY, visibleFrame.maxY - size.height - margin))
    }

    /// The window's origin so the slab, which sits `shadowRoom` inside the window, is `margin` from the top and
    /// right edges. The window itself is then flush with the corner.
    public static func windowOrigin(windowSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        origin(size: windowSize, visibleFrame: visibleFrame,
               margin: ScribeMeetingCardMetrics.margin - ScribeMeetingCardMetrics.shadowRoom)
    }
}
