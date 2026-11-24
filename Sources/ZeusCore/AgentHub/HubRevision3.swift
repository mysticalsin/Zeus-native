import Foundation

/// Revision 3 names for one hub decision. Tiers, actions, keys, and the countdown and undo windows.
/// Nothing here reads a clock or changes a queue. The machine that applies a pair lives beside this file.

public enum HubRiskTier: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case low
    case high
    case destructive

    public var title: String {
        switch self {
        case .low: "Low"
        case .high: "High"
        case .destructive: "Destructive"
        }
    }
}

public enum HubDecisionAction: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case allowOnce
    case allowForThisSession
    case deny
    case denyWithNote

    public var title: String {
        switch self {
        case .allowOnce: "Allow once"
        case .allowForThisSession: "Allow for this session"
        case .deny: "Deny"
        case .denyWithNote: "Deny with note"
        }
    }

    /// Allow once and allow for this session approve. Deny, with or without a note, does not.
    /// The countdown expires as deny, so an approval is never what the timer chooses.
    public var isApproval: Bool {
        switch self {
        case .allowOnce, .allowForThisSession: true
        case .deny, .denyWithNote: false
        }
    }
}

public enum HubDecisionKey: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case `return`
    case two
    case escape
    case three
    case four
    case shiftEscape
    case undo

    /// The action a single decision key names. Shift-Escape denies the queue, and U undoes.
    /// Neither of those is an action on the one showing decision.
    public var action: HubDecisionAction? {
        switch self {
        case .`return`: .allowOnce
        case .two: .allowForThisSession
        case .escape, .three: .deny
        case .four: .denyWithNote
        case .shiftEscape, .undo: nil
        }
    }
}

/// Why the 12 second countdown is holding still. Any one of these is enough.
public enum HubCountdownPause: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case hover
    case focus
    case voiceOverFocus

    public var title: String {
        switch self {
        case .hover: "hover"
        case .focus: "focus"
        case .voiceOverFocus: "VoiceOver focus"
        }
    }
}

/// Fixed windows from the approved revision. Counts are milliseconds so 1.2 s is 1,200
/// and 2.0 s is 2,000, with no wall clock behind them.
public enum HubRevision3Timing {
    /// Destructive approval requires a press at least this long. 1,199 ms does not approve.
    public static let destructiveHoldMilliseconds = 1_200
    /// The countdown. It ends in `countdownExpiry`, which is deny.
    public static let countdownMilliseconds = 12_000
    /// After a decision, nothing runs until this window has passed. Undo is open until then.
    public static let undoMilliseconds = 2_000
    /// A deny-with-note note, in extended grapheme clusters. 280 is kept. 281 is not.
    public static let noteCharacterLimit = 280
    /// The countdown never approves.
    public static let countdownExpiry = HubDecisionAction.deny
}

/// Which key does what. Command is never a shortcut. A key does nothing unless its window is showing.
public enum HubDecisionKeys {
    public static func decision(
        _ key: HubDecisionKey,
        command: Bool,
        decisionShowing: Bool
    ) -> HubDecisionAction? {
        guard decisionShowing, command == false else { return nil }
        return key.action
    }

    public static func deniesAllQueued(key: HubDecisionKey, command: Bool, decisionShowing: Bool) -> Bool {
        decisionShowing && command == false && key == .shiftEscape
    }

    public static func undoes(key: HubDecisionKey, command: Bool, undoShowing: Bool) -> Bool {
        undoShowing && command == false && key == .undo
    }
}
