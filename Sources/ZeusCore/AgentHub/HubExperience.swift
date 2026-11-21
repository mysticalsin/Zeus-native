/// The hub experience contract. Later list, transcript, and decision views match these labels.
/// Nothing here draws, moves focus, schedules a timer, or reads a socket.

/// Accessibility labels for the controls those views draw. A row and a group header are composed,
/// because they include the session's own name.
public enum HubAccessibilityLabel {
    /// The existing unfilled decision button.
    public static let deny = "Deny"
    /// The existing filled decision button.
    public static let approve = "Approve"
    /// The scrolling transcript in the detail.
    public static let transcript = "Transcript"
    /// The code block button. This is the label already on that button.
    public static let copy = "Copy code"
    /// The reply field. The placeholder is the same word.
    public static let reply = "Reply"
    /// The reply field's send button.
    public static let send = "Send"
    /// The existing jump button on a row.
    public static let open = "Open"
    /// The existing dismiss button. Dismiss keeps the transcript.
    public static let dismiss = "Dismiss"
}

/// Where a page change starts. Reduce Motion is zero offset and scale 1.
public struct HubMotionRequest: Equatable, Sendable {
    public var offset: Double
    public var scale: Double

    public init(offset: Double, scale: Double) {
        self.offset = offset
        self.scale = scale
    }
}

/// One look at the closed panel. The idle predicate reads this and does not sample the machine itself.
public struct HubIdleSample: Equatable, Sendable {
    public var panelClosed: Bool
    public var approvalShowing: Bool
    public var socketReadInProgress: Bool
    /// A timer of `HubExperience.clockTickSeconds` is on the run loop.
    public var oneSecondTimerScheduled: Bool
    public var waveDisplayLinkRunning: Bool
    /// Share of one core, in the same unit as `HubExperience.idleBudgetPercentOfOneCore`.
    public var percentOfOneCore: Double

    public init(
        panelClosed: Bool,
        approvalShowing: Bool,
        socketReadInProgress: Bool,
        oneSecondTimerScheduled: Bool,
        waveDisplayLinkRunning: Bool,
        percentOfOneCore: Double
    ) {
        self.panelClosed = panelClosed
        self.approvalShowing = approvalShowing
        self.socketReadInProgress = socketReadInProgress
        self.oneSecondTimerScheduled = oneSecondTimerScheduled
        self.waveDisplayLinkRunning = waveDisplayLinkRunning
        self.percentOfOneCore = percentOfOneCore
    }
}

/// Focus order, accessibility labels, Reduce Motion, and the open and idle budgets.
public enum HubExperience {
    /// The page rise, in points, when Reduce Motion is off. The existing page change uses this rise.
    public static let pageRisePoints = 8.0
    /// The page scale when Reduce Motion is off. The existing page change uses this scale.
    public static let pageScale = 0.985
    /// From the click that opens the hub to the first frame of it, in milliseconds.
    /// A sample at this value meets the budget. One millisecond more does not.
    public static let openBudgetMilliseconds = 100
    /// Idle share of one core, in percent, while the panel is closed.
    /// A sample at this value meets the budget. One percent more does not.
    public static let idleBudgetPercentOfOneCore = 1.0
    /// The one shared row clock. It is not scheduled while the panel is closed.
    public static let clockTickSeconds = 1

    /// Focus for one session. A selected session that is also showing an approval is
    /// group header, row, Deny, Approve, transcript, reply, Send, Open.
    /// Shift-Tab walks that order backwards. The tab row stays where the page left it.
    public static func focusOrder(sessionSelected: Bool, approvalShowing: Bool) -> [HubFocusTarget] {
        var order: [HubFocusTarget] = [.groupHeader, .row]
        if approvalShowing {
            order.append(contentsOf: [.deny, .approve])
        }
        if sessionSelected {
            order.append(.transcript)
            if !approvalShowing {
                order.append(.copy)
            }
            order.append(contentsOf: [.reply, .send, .open])
        }
        return order
    }

    /// The fixed label for a control. A group header and a row use the composed labels below.
    /// The tab row, the picker, and focus outside the page keep the labels they already have.
    public static func accessibilityLabel(for target: HubFocusTarget) -> String? {
        switch target {
        case .deny: HubAccessibilityLabel.deny
        case .approve: HubAccessibilityLabel.approve
        case .transcript: HubAccessibilityLabel.transcript
        case .copy: HubAccessibilityLabel.copy
        case .reply: HubAccessibilityLabel.reply
        case .send: HubAccessibilityLabel.send
        case .open: HubAccessibilityLabel.open
        case .outside, .tabRow, .groupHeader, .row, .picker: nil
        }
    }

    /// One session row, read as one element. Selected is a trait, so it does not change this label.
    /// Meeting mode passes `hidesProject` and the project is left out. A clock that has not started passes nil.
    public static func sessionRowLabel(
        agent: String,
        project: String,
        status: HubSessionStatus,
        elapsedSeconds: Int?,
        hidesProject: Bool = false
    ) -> String {
        var parts: [String] = []
        if !agent.isEmpty { parts.append(agent) }
        if !hidesProject, !project.isEmpty { parts.append(project) }
        if let word = status.visibleWord { parts.append(word) }
        if let elapsedSeconds { parts.append(spokenElapsed(seconds: elapsedSeconds)) }
        return parts.joined(separator: ", ")
    }

    /// A group header. A collapsed header keeps the most urgent row's elapsed time. An expanded header does not,
    /// because the rows under it already say the time.
    public static func groupHeaderLabel(
        name: String,
        count: Int,
        urgentStatus: HubSessionStatus,
        elapsedSeconds: Int?,
        expanded: Bool
    ) -> String {
        var parts: [String] = []
        if !name.isEmpty { parts.append(name) }
        if let word = urgentStatus.visibleWord { parts.append(word) }
        parts.append(count == 1 ? "1 session" : "\(count) sessions")
        if !expanded, let elapsedSeconds { parts.append(spokenElapsed(seconds: elapsedSeconds)) }
        parts.append(expanded ? "expanded" : "collapsed")
        return parts.joined(separator: ", ")
    }

    /// The page change. Reduce Motion asks for no rise and no scale.
    public static func motionRequest(reduceMotion: Bool) -> HubMotionRequest {
        if reduceMotion { return HubMotionRequest(offset: 0, scale: 1) }
        return HubMotionRequest(offset: pageRisePoints, scale: pageScale)
    }

    /// A pressed control. Reduce Motion keeps the dim and does not scale.
    public static func pressScale(reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : MotionTokens.pressScale
    }

    /// The five bars travel only while the row is Running and Reduce Motion is off.
    public static func waveMoves(status: HubSessionStatus, reduceMotion: Bool) -> Bool {
        status == .running && !reduceMotion
    }

    /// True when the first hub frame arrived inside the open budget.
    public static func meetsOpenBudget(milliseconds: Int) -> Bool {
        milliseconds >= 0 && milliseconds <= openBudgetMilliseconds
    }

    /// True when a closed panel's share of one core is inside the idle budget.
    public static func meetsIdleBudget(percentOfOneCore: Double) -> Bool {
        percentOfOneCore.isFinite
            && percentOfOneCore >= 0
            && percentOfOneCore <= idleBudgetPercentOfOneCore
    }

    /// The idle budget predicate. False when a one-second timer is scheduled while the panel is closed,
    /// and false when an approval is showing, a socket read is in progress, or the wave's display link is running.
    /// An open panel is not this sample.
    public static func isIdle(_ sample: HubIdleSample) -> Bool {
        guard sample.panelClosed,
              !sample.approvalShowing,
              !sample.socketReadInProgress,
              !sample.oneSecondTimerScheduled,
              !sample.waveDisplayLinkRunning
        else { return false }
        return meetsIdleBudget(percentOfOneCore: sample.percentOfOneCore)
    }

    /// "3 minutes 12 seconds", "1 minute", "0 seconds". A negative count is spoken as zero.
    private static func spokenElapsed(seconds: Int) -> String {
        let whole = max(0, seconds)
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let secs = whole % 60
        var parts: [String] = []
        if hours == 1 { parts.append("1 hour") }
        else if hours > 1 { parts.append("\(hours) hours") }
        if minutes == 1 { parts.append("1 minute") }
        else if minutes > 1 { parts.append("\(minutes) minutes") }
        if secs == 1 { parts.append("1 second") }
        else if secs > 1 { parts.append("\(secs) seconds") }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }

    /// Revision 3 actions, in VoiceOver order. The older deny and approve targets stay on the focus enum.
    public static func revision3DecisionOrder() -> [String] {
        ["Allow once", "Allow for this session", "Deny", "Deny with note"]
    }

    /// The 12 second countdown ends in Deny. It never approves.
    public static let revision3CountdownExpiresByApproving = false
    public static let revision3CountdownSeconds = 12
    public static let revision3UndoSeconds = 2
    /// Destructive approval holds for 1.2 seconds.
    public static let revision3DestructiveHoldSeconds = 1.2
    public static let revision3NoteCharacterLimit = 280
    /// Command is never a shortcut.
    public static let revision3CommandKeyIsShortcut = false
    public static let revision3PauseReasons = ["hover", "focus", "VoiceOver focus"]

    /// Reduce Motion keeps the countdown text and does not animate it.
    public static func revision3CountdownAnimates(reduceMotion: Bool) -> Bool { !reduceMotion }

    public static func revision3CountdownTextRemains(reduceMotion: Bool) -> Bool { reduceMotion || true }

    /// The same page motion. Reduce Motion is zero offset and scale 1. The spring is unchanged.
    public static func revision3Motion(reduceMotion: Bool) -> HubMotionRequest {
        motionRequest(reduceMotion: reduceMotion)
    }

    public static func revision3KeysActive(decisionShowing: Bool) -> Bool { decisionShowing }

    /// Escape and 3 deny. Keys do nothing unless a decision, or the undo window, is showing.
    /// A command modifier is not a shortcut. ZB-UIUX-ESCAPE-001.
    public static func revision3Key(
        _ key: String,
        command: Bool,
        decisionShowing: Bool = false,
        undoShowing: Bool = false
    ) -> String? {
        if command { return nil }
        if undoShowing, key == "u" { return "Undo" }
        guard decisionShowing else { return nil }
        switch key {
        case "return": return "Allow once"
        case "2": return "Allow for this session"
        case "escape", "3": return "Deny"
        case "4": return "Deny with note"
        case "shiftEscape": return "Deny all queued"
        default: return nil
        }
    }

    public static func revision3QueueCount(_ count: Int) -> String {
        count == 1 ? "1 waiting" : "\(max(count, 0)) waiting"
    }

    public static func revision3CountdownSentence(seconds: Int, paused: Bool) -> String {
        let body = "\(max(seconds, 0)) s left, then it's denied."
        return paused ? "Countdown paused. \(body)" : body
    }

    /// Identifiers for the unlabeled approval controls.
    /// ZB-UIUX-A11Y-030 Accept and ZB-UIUX-A11Y-034 Approve are Allow once.
    /// ZB-UIUX-A11Y-032 is Deny when details are hidden. ZB-UIUX-A11Y-033 is Deny.
    /// ZB-UIUX-ESCAPE-001 is the same Deny. ZB-UIUX-DECISION-001 is the row.
    public static func revision3Identifier(forFinding finding: String) -> String? {
        switch finding {
        case "ZB-UIUX-DECISION-001": return "hub.decision.row"
        case "ZB-UIUX-A11Y-030", "ZB-UIUX-A11Y-034": return "hub.decision.allow-once"
        case "ZB-UIUX-A11Y-032": return "hub.decision.deny.hidden"
        case "ZB-UIUX-A11Y-033", "ZB-UIUX-ESCAPE-001": return "hub.decision.deny"
        default: return nil
        }
    }

    public static func revision3VoiceOverLabel(forIdentifier identifier: String) -> String? {
        switch identifier {
        case "hub.decision.allow-once": return "Allow once"
        case "hub.decision.allow-session": return "Allow for this session"
        case "hub.decision.deny", "hub.decision.deny.hidden": return "Deny"
        case "hub.decision.deny-note": return "Deny with note"
        case "hub.decision.row": return "Decision"
        default: return nil
        }
    }
}
