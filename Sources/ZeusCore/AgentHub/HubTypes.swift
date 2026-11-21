import Foundation

/// Names for the chat and agent hub. Status, cause, screen, and event labels only.
/// The machines that apply the transition tables live in later files. Nothing here changes a state.

/// A hub name stored as its raw string. An unknown string is nil.
public protocol HubStoredLabel: RawRepresentable, CaseIterable, Codable, Equatable, Hashable, Sendable where RawValue == String {
    var storedLabel: String { get }
    init?(storedLabel: String)
}

extension HubStoredLabel {
    public var storedLabel: String { rawValue }
    public init?(storedLabel: String) { self.init(rawValue: storedLabel) }
}

/// Why a session is in `error`. Silence past the stall limit is `quiet`. A hard failure is `failed`.
public enum HubErrorCause: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case failed
    case quiet
}

/// The row clock, apart from being hidden while the panel is closed.
public enum HubClockPhase: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case notStarted
    case ticking
    case frozen
}

/// What a session is doing. `error` carries a `HubErrorCause`.
public enum HubSessionStatus: Equatable, Hashable, Sendable, CaseIterable {
    case absent
    case loading
    case running
    case waitingForInput
    case needsApproval
    case done
    case error(HubErrorCause)

    public static var allCases: [HubSessionStatus] {
        [.absent, .loading, .running, .waitingForInput, .needsApproval, .done, .error(.failed), .error(.quiet)]
    }

    /// `error.failed` and `error.quiet` keep the cause in the label. Any other string is nil.
    public var storedLabel: String {
        switch self {
        case .absent: "absent"
        case .loading: "loading"
        case .running: "running"
        case .waitingForInput: "waitingForInput"
        case .needsApproval: "needsApproval"
        case .done: "done"
        case .error(let cause): "error." + cause.storedLabel
        }
    }

    public init?(storedLabel: String) {
        switch storedLabel {
        case "absent": self = .absent
        case "loading": self = .loading
        case "running": self = .running
        case "waitingForInput": self = .waitingForInput
        case "needsApproval": self = .needsApproval
        case "done": self = .done
        case "error.failed": self = .error(.failed)
        case "error.quiet": self = .error(.quiet)
        default: return nil
        }
    }

    /// The five turn words, in the order a row uses them. Loading is "Announced" and is not one of the five.
    public static let visibleWords = ["Running", "Waiting for input", "Needs approval", "Done", "Error"]

    public var visibleWord: String? {
        switch self {
        case .running: "Running"
        case .waitingForInput: "Waiting for input"
        case .needsApproval: "Needs approval"
        case .done: "Done"
        case .error: "Error"
        case .loading: "Announced"
        case .absent: nil
        }
    }

    /// Most urgent first. `absent` is not a row. Both error causes share `error`.
    public static let urgencyLabels = ["needsApproval", "error", "waitingForInput", "running", "done", "loading"]

    public var clockPhase: HubClockPhase? {
        switch self {
        case .absent: nil
        case .loading: .notStarted
        case .running, .waitingForInput, .needsApproval: .ticking
        case .done, .error: .frozen
        }
    }
}

extension HubSessionStatus: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let label = try container.decode(String.self)
        guard let status = HubSessionStatus(storedLabel: label) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown session status.")
        }
        self = status
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storedLabel)
    }
}

/// What the session machine is told. Applying a pair is the machine's job.
public enum HubSessionEvent: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case announced
    case promptStarted
    case ended
    case toolActivity
    case questionAsked
    case approvalRequested
    case finished
    case failed
    /// Silence past the stall limit.
    case quietForTheStallLimit
    case answerAccepted
    case approved
    case denied
    case timedOut
    case dismissed
    /// A later event that is not itself a new prompt. Clears a quiet error.
    case activity
}

/// Which Agents page is on screen. Ready covers groups, a selection, an inline approval, and an error row.
public enum HubScreen: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case empty
    case loading
    case ready
    case connectionError

    public var sentence: String? {
        switch self {
        case .empty: "Nothing running"
        case .loading: "Connecting…"
        case .connectionError: "Agents aren't connected."
        case .ready: nil
        }
    }

    public var detail: String? {
        switch self {
        case .empty: "Start a chat and it shows up here."
        case .loading, .connectionError, .ready: nil
        }
    }

    /// New chat on empty. Try again on a connection error. Nowhere else.
    public var actionTitle: String? {
        switch self {
        case .empty: "New chat"
        case .connectionError: "Try again"
        case .loading, .ready: nil
        }
    }
}

/// What the screen machine is told. `newChat` keeps the hub phase.
public enum HubScreenEvent: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    /// "socket opened, no sessions"
    case socketOpenedNoSessions
    case socketOpening
    /// "at least one session"
    case atLeastOneSession
    /// "a session arrives"
    case sessionArrived
    /// "last session ends"
    case lastSessionEnded
    case socketFailed
    case tryAgain
    /// "socket opened", from a connection error. The next screen follows `HubScreenGuard.sessionCount`.
    case socketOpened
    case newChat
}

/// Guards named beside a screen event.
public enum HubScreenGuard: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case noSessions
    case atLeastOneSession
    /// "sessions may still be on screen"
    case sessionsMayRemain
    case chatTab
    /// "from the session count"
    case sessionCount
}

/// One live approval, plus requests waiting behind it.
public enum HubApprovalStatus: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case idle
    case showing
    case queued
}

/// What the approval machine is told. Ask is a keyboard verdict, not a new button.
public enum HubApprovalEvent: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case request
    case approve
    case deny
    case timeout
    case ask
    /// The showing approval closed, so a queued request can show.
    case showingClosed
}

public enum HubApprovalVerdict: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case allow
    case deny
    case ask
}

/// One transcript: a session's, or a Zeus conversation's. They do not share a store.
public enum HubTranscriptStatus: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case idle
    case streaming
    case settled
    case failed
}

public enum HubTranscriptEvent: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case send
    case sendBlank
    case delta
    case finish
    /// Finish with no text.
    case finishEmpty
    case stop
    case failure
}

/// Who a stored line belongs to. A failed line is plain text, not markdown.
public enum HubLineRole: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case person
    case agent
    case failed
    case stopped
}

/// Fixed transcript lines the target names.
public enum HubTranscriptNotice: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case noAnswer = "No answer came back."
    case stopped = "Stopped"
}

/// A typed reply on an agent row, before and after the approval.
public enum HubReplyStatus: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case idle
    case drafting
    case unsupported
    case awaitingDecision
    case sending
    case failed
}

public enum HubReplyEvent: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case textChanged
    case send
    case denied
    case timedOut
    case approved
    case scriptTyped
    case scriptFailed
}

public enum HubReplyGuard: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case emptyAfterCleaning
    case destinationCannotTakeText
    case destinationCanTakeText
}

/// Receipts the reply machine shows. The stored label is the sentence.
public enum HubReplyReceipt: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case typeSomethingFirst = "Type something first."
    case notSent = "Not sent."
    case sent = "Sent."
    case openDestination = "This terminal can't take typed replies. Open it and reply there."
    case openSession = "I couldn't find that terminal tab. Open it and reply there."
    /// The line contains a zero-width or bidirectional mark. It is kept, not stripped.
    case hiddenCharacter = "That line has a hidden or bidirectional character, so it was not sent."
    case tabChanged = "That terminal tab changed, so nothing was typed."
    case tabVanished = "That terminal tab is gone, so nothing was typed."
    case bareShell = "That tab is a shell prompt, so nothing was typed."
    case foregroundUnknown = "Zeus could not see what is running in that tab, so nothing was typed."
}

public enum HubGroupStatus: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case collapsed
    case expanded
}

public enum HubGroupEvent: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case activateHeader
    case sessionsChanged
    case lostLastSession
    case firstLoad
}

/// The master sound switch. Off, nothing plays.
public enum HubSoundStatus: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case silent
    case armed
    case playing
}

public enum HubSoundEvent: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case optIn
    case optOut
    /// A cue the existing policy allows.
    case cueAllowed
    /// Inside the 3 second window, a finish under 20 seconds, or a start while start cues are off.
    case cueSuppressed
    case soundEnded
}

public enum HubSoundCue: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case start
    case done
    case approval
    case answer
}

public enum HubSoundGuard: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case insideThreeSecondWindow
    case finishUnderTwentySeconds
    case startChimesOff
}

/// Banner rows. Separate from the sound switch. Needs-approval and waiting-for-input do not banner.
public enum HubBannerEvent: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case failed
    case quietError
    case done
    case needsApproval
    case waitingForInput
}

/// A place focus can rest, and the order VoiceOver walks.
public enum HubFocusTarget: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case outside
    case tabRow
    case groupHeader
    case row
    case picker
    case deny
    case approve
    case transcript
    case copy
    case reply
    case send
    case open

    /// A selected session that is also showing an approval.
    public static let selectedApprovalOrder: [HubFocusTarget] = [
        .groupHeader, .row, .deny, .approve, .transcript, .reply, .send, .open,
    ]

    /// Screen order when no approval is inserted after the row.
    public static let screenOrder: [HubFocusTarget] = [
        .tabRow, .groupHeader, .row, .transcript, .copy, .reply, .send, .open,
    ]
}

public enum HubFocusEvent: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case pageOpened
    case activate
    case up
    case down
    case `return`
    case escape
    case approveKey
    case denyKey
    case askKey
}

public enum HubFocusGuard: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case pickerClosed
    case replyUnfocused
    case listFocused
    case fieldNonEmpty
    case answerKeysOn
    case pickerOpen
    case rowSelected
    case nothingSelected
}
