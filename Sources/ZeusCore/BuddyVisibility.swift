import Foundation

/// Settings > Show Zeus beside the pointer.
public enum BuddyShow: String, CaseIterable, Identifiable, Sendable {
    case always, onCall, never

    public var id: String { rawValue }
    public static let defaultsKey = "buddy.show"

    public var title: String {
        switch self {
        case .always: "Always"
        case .onCall: "When I call him"
        case .never: "Never"
        }
    }

    /// Anything unknown (or never saved) is the default: only when called.
    public static func stored(_ raw: String?) -> BuddyShow { raw.flatMap(BuddyShow.init(rawValue:)) ?? .onCall }
}

/// When the cursor buddy is on screen. With "Only when I call him" he is hidden until something
/// calls him (the talk shortcut, "Hey Zeus", a voice turn, pointing or a drive), stays while that
/// lasts, and fades out `linger` seconds after the last reason ends.
public struct BuddyVisibility: Equatable, Sendable {
    public enum Reason: String, Hashable, Sendable {
        /// The talk shortcut or the wake word, before the turn itself has started.
        case call
        /// Listening, thinking or speaking.
        case turn
        /// Flying to a spot, pointing, or flying back (drive and walkthroughs included).
        case pointing
        /// A caption of what Zeus said is still on screen.
        case caption
    }

    public static let linger: TimeInterval = 2

    public var policy: BuddyShow
    public private(set) var reasons: Set<Reason> = []
    public private(set) var lingerUntil: Date?

    public init(policy: BuddyShow = .onCall) { self.policy = policy }

    public mutating func begin(_ reason: Reason) {
        reasons.insert(reason)
        lingerUntil = nil
    }

    public mutating func end(_ reason: Reason, at now: Date) {
        guard reasons.remove(reason) != nil else { return }
        if reasons.isEmpty { lingerUntil = now.addingTimeInterval(Self.linger) }
    }

    public func isVisible(at now: Date) -> Bool {
        switch policy {
        case .always: return true
        case .never: return false
        case .onCall:
            if !reasons.isEmpty { return true }
            return lingerUntil.map { now < $0 } ?? false
        }
    }

    /// When the buddy next needs rechecking, so the fade-out can be scheduled; nil when nothing is pending.
    public func nextChange(after now: Date) -> Date? {
        guard policy == .onCall, reasons.isEmpty, let lingerUntil, lingerUntil > now else { return nil }
        return lingerUntil
    }
}
