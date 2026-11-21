import Foundation

/// What the inline reply row shows, and which press releases a line.
/// Approve is the only release. Deny, Cancel, Escape, and the timeout type nothing.
/// The 30 second wait is the one the hub already uses. This type does not change it.
public struct HubPendingReplyModel: Equatable, Sendable {
    public static let waitSeconds: TimeInterval = 30
    /// Summary, then Deny, then Cancel, then Approve. Approve is last so it is not the first stop.
    public static let focusOrder: [HubPendingReplyFocus] = [.summary, .deny, .cancel, .approve]
    public static let primary = HubPendingReplyFocus.approve

    private var id = ""
    private var destination = ""
    private var line = ""
    private var deadline: TimeInterval = 0
    private var open = false

    public init() {}

    /// Shows the cleaned line. A second call for the same id keeps the original deadline.
    /// Nothing is released from here, including the moment the row appears.
    public mutating func present(
        _ offer: HubPendingReplyOffer,
        at now: TimeInterval,
        deadline: TimeInterval
    ) -> HubPendingReplyVerdict {
        let bound = offer.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bound.isEmpty, now.isFinite, deadline.isFinite else { return .ignore }
        guard let cleaned = Self.typeableLine(offer.draft) else { return .ignore }
        if open, id == bound { return .ignore }
        id = bound
        destination = offer.destination
        line = cleaned
        self.deadline = deadline
        open = true
        return .ignore
    }

    /// `return` releases only while Approve is focused. Any other id is ignored.
    /// A row that already released, or already closed, releases nothing again.
    public mutating func decide(
        _ action: HubPendingReplyAction,
        id: String,
        focus: HubPendingReplyFocus?,
        at _: TimeInterval
    ) -> HubPendingReplyVerdict {
        guard open, self.id == id, !id.isEmpty else { return .ignore }
        switch action {
        case .appear:
            return .ignore
        case .return:
            guard focus == .approve else { return .ignore }
            return release()
        case .approve:
            return release()
        case .deny, .escape:
            return close(.deny)
        case .cancel:
            return close(.cancel)
        case .timeout:
            return close(.timeout)
        }
    }

    public func displayed(at now: TimeInterval) -> HubPendingReplyRow? {
        guard open, !id.isEmpty else { return nil }
        return HubPendingReplyRow(
            id: id,
            destination: destination,
            line: line,
            secondsLeft: Self.secondsLeft(deadline: deadline, now: now),
            caption: Self.caption(deadline: deadline, now: now),
            accessibilityLabel: Self.summaryLabel(destination: destination, line: line),
            accessibilityHint: Self.summaryHint(destination: destination, line: line, deadline: deadline, now: now),
            buttons: Self.buttons(destination: destination, line: line)
        )
    }

    /// Reduce Motion keeps the row where it is and changes opacity only. Otherwise it may travel.
    public static func motion(reduceMotion: Bool) -> HubPendingReplyMotion {
        if reduceMotion {
            return HubPendingReplyMotion(opacity: 1, offset: 0, usesSpring: false)
        }
        return HubPendingReplyMotion(opacity: 1, offset: 8, usesSpring: true)
    }

    /// Higher values are read first. The order is `focusOrder`.
    public static func sortPriority(_ focus: HubPendingReplyFocus) -> Double {
        guard let index = focusOrder.firstIndex(of: focus) else { return 0 }
        return Double(focusOrder.count - index)
    }

    private mutating func release() -> HubPendingReplyVerdict {
        let released = id
        let typed = line
        open = false
        return .release(id: released, line: typed)
    }

    private mutating func close(_ reason: HubPendingReplyWithhold) -> HubPendingReplyVerdict {
        let closed = id
        open = false
        return .withhold(id: closed, reason: reason)
    }

    private static func typeableLine(_ draft: String) -> String? {
        guard let cleaned = HubDecision.cleanedLine(draft), HubReplyTyping.canType(cleaned) else { return nil }
        return cleaned
    }

    private static func secondsLeft(deadline: TimeInterval, now: TimeInterval) -> Int {
        guard now.isFinite, deadline.isFinite else { return 0 }
        let remaining = deadline - now
        guard remaining > 0 else { return 0 }
        return min(Int(waitSeconds), Int(ceil(remaining)))
    }

    private static func caption(deadline: TimeInterval, now: TimeInterval) -> String {
        "\(secondsLeft(deadline: deadline, now: now)) s left, then it's denied."
    }

    private static func spoken(_ destination: String) -> String {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "this session" : trimmed
    }

    private static func summaryLabel(destination: String, line: String) -> String {
        "Pending reply to \(spoken(destination)). \(line)"
    }

    private static func summaryHint(destination: String, line: String, deadline: TimeInterval, now: TimeInterval) -> String {
        "Approve types \(line) into \(spoken(destination)). Deny, Cancel, and the timeout type nothing. \(caption(deadline: deadline, now: now))"
    }

    private static func buttons(destination: String, line: String) -> [HubPendingReplyButton] {
        let place = spoken(destination)
        return [
            HubPendingReplyButton(
                focus: .deny,
                action: .deny,
                title: "Deny",
                label: "Deny. \(line). \(place)",
                hint: "Does not type \(line) into \(place).",
                isPrimary: false
            ),
            HubPendingReplyButton(
                focus: .cancel,
                action: .cancel,
                title: "Cancel",
                label: "Cancel. \(line). \(place)",
                hint: "Does not type \(line) into \(place). The draft stays.",
                isPrimary: false
            ),
            HubPendingReplyButton(
                focus: .approve,
                action: .approve,
                title: "Approve",
                label: "Approve. \(line). \(place)",
                hint: "Types \(line) into \(place).",
                isPrimary: true
            ),
        ]
    }
}

public struct HubPendingReplyOffer: Equatable, Sendable {
    public var id: String
    public var destination: String
    public var draft: String

    public init(id: String, destination: String, draft: String) {
        self.id = id
        self.destination = destination
        self.draft = draft
    }
}

public enum HubPendingReplyAction: String, Equatable, Sendable, CaseIterable {
    case approve
    case deny
    case cancel
    case timeout
    case escape
    case appear
    case `return`
}

/// Where VoiceOver and the keyboard rest on the pending row.
public enum HubPendingReplyFocus: String, Equatable, Sendable, CaseIterable {
    case summary
    case deny
    case cancel
    case approve
}

public enum HubPendingReplyWithhold: String, Equatable, Sendable {
    case deny
    case cancel
    case timeout
}

public enum HubPendingReplyVerdict: Equatable, Sendable {
    case release(id: String, line: String)
    case withhold(id: String, reason: HubPendingReplyWithhold)
    case ignore
}

public struct HubPendingReplyButton: Equatable, Sendable, Identifiable {
    public var focus: HubPendingReplyFocus
    public var action: HubPendingReplyAction
    public var title: String
    public var label: String
    public var hint: String
    public var isPrimary: Bool
    public var id: HubPendingReplyFocus { focus }

    public init(
        focus: HubPendingReplyFocus,
        action: HubPendingReplyAction,
        title: String,
        label: String,
        hint: String,
        isPrimary: Bool
    ) {
        self.focus = focus
        self.action = action
        self.title = title
        self.label = label
        self.hint = hint
        self.isPrimary = isPrimary
    }
}

public struct HubPendingReplyRow: Equatable, Sendable {
    public var id: String
    public var destination: String
    public var line: String
    public var secondsLeft: Int
    public var caption: String
    public var accessibilityLabel: String
    public var accessibilityHint: String
    public var buttons: [HubPendingReplyButton]

    public init(
        id: String,
        destination: String,
        line: String,
        secondsLeft: Int,
        caption: String,
        accessibilityLabel: String,
        accessibilityHint: String,
        buttons: [HubPendingReplyButton]
    ) {
        self.id = id
        self.destination = destination
        self.line = line
        self.secondsLeft = secondsLeft
        self.caption = caption
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.buttons = buttons
    }
}

public struct HubPendingReplyMotion: Equatable, Sendable {
    public var opacity: Double
    public var offset: Double
    public var usesSpring: Bool

    public init(opacity: Double, offset: Double, usesSpring: Bool) {
        self.opacity = opacity
        self.offset = offset
        self.usesSpring = usesSpring
    }
}
