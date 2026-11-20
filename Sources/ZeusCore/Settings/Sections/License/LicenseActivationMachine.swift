import Foundation

/// The license key as the settings card holds it. Descriptions, debug text and mirrors stay redacted.
public struct LicenseKeyDraft: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private var value: String

    public init(_ value: String = "") { self.value = value }

    public var isEmpty: Bool { normalized.isEmpty }

    public var normalized: String { LicenseKeyPrivacy.compact(value) }

    public var masked: String { LicenseKeyPrivacy.mask(value) }

    /// Explicit read for the reveal control and for the activate or copy handoff.
    public func reveal() -> String { value }

    public var description: String { isEmpty ? "LicenseKeyDraft(empty)" : "LicenseKeyDraft(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

public enum LicenseKeyPrivacy {
    public static let visiblePrefix = 5
    public static let visibleSuffix = 4

    public static func compact(_ text: String) -> String { String(text.filter { !$0.isWhitespace }) }

    public static func mask(_ key: String) -> String {
        let compact = compact(key)
        guard !compact.isEmpty else { return "" }
        if compact.count <= visiblePrefix + visibleSuffix { return String(repeating: "•", count: compact.count) }
        return "\(compact.prefix(visiblePrefix))••••\(compact.suffix(visibleSuffix))"
    }

    /// True when `text` still contains a real key. Short fragments are not keys.
    public static func exposes(_ text: String, key: String) -> Bool {
        let compact = compact(key)
        guard compact.count >= 8 else { return false }
        return text.contains(compact)
    }

    public static func scrub(_ text: String, secrets: [String]) -> String {
        var result = text
        for secret in secrets {
            let compact = compact(secret)
            guard compact.count >= 8 else { continue }
            if result.contains(secret) { result = result.replacingOccurrences(of: secret, with: mask(secret)) }
            if compact != secret, result.contains(compact) { result = result.replacingOccurrences(of: compact, with: mask(compact)) }
        }
        return scrubOpaqueKeys(result)
    }

    /// Masks a key-shaped token even when the caller no longer has the original secret.
    public static func scrubOpaqueKeys(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix("ZEUS1"), let start = text.index(index, offsetBy: 5, limitedBy: text.endIndex) {
                var end = start
                while end < text.endIndex, !text[end].isWhitespace { end = text.index(after: end) }
                let token = String(text[index..<end])
                if compact(token).count >= 8 {
                    result += mask(token)
                    index = end
                    continue
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }
}

public enum LicenseActivationPhase: String, Equatable, Sendable, CaseIterable {
    case unlicensed, trial, activating, active, releasing, error
}

/// What the existing license store reported. This value is not a second store.
public struct LicenseCardFacts: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var status: LicenseStatus
    public var storedKey: LicenseKeyDraft
    public var activationPending: Bool
    public var serverNeedsReentry: Bool
    public var serverConfigured: Bool
    public var seatLabel: String?
    public var deactivationError: String?
    public var notice: String?

    public init(status: LicenseStatus, storedKey: LicenseKeyDraft = LicenseKeyDraft(), activationPending: Bool = false,
                serverNeedsReentry: Bool = false, serverConfigured: Bool = false, seatLabel: String? = nil,
                deactivationError: String? = nil, notice: String? = nil) {
        self.status = status
        self.storedKey = storedKey
        self.activationPending = activationPending
        self.serverNeedsReentry = serverNeedsReentry
        self.serverConfigured = serverConfigured
        self.seatLabel = seatLabel
        self.deactivationError = deactivationError
        self.notice = notice
    }

    public var description: String { "LicenseCardFacts(status: \(status), stored: \(storedKey), pending: \(activationPending))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["status": String(describing: status), "stored": storedKey.description], displayStyle: .struct)
    }
}

public struct LicenseActivationFailure: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var message: String
    public var resume: LicenseActivationPhase

    public init(message: String, resume: LicenseActivationPhase) {
        self.message = message
        self.resume = resume
    }

    public var description: String { "LicenseActivationFailure(resume: \(resume.rawValue))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["resume": resume.rawValue], displayStyle: .struct) }
}

public struct LicenseActivationState: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var phase: LicenseActivationPhase
    public var draft: LicenseKeyDraft
    public var facts: LicenseCardFacts
    public var revealed: Bool
    public var releaseArmed: Bool
    public var enteringReplacement: Bool
    public var failure: LicenseActivationFailure?
    public var copiedAnnouncement: String?
    public var purchaseEmphasis: Bool
    public var reduceMotion: Bool

    public init(phase: LicenseActivationPhase, draft: LicenseKeyDraft = LicenseKeyDraft(), facts: LicenseCardFacts,
                revealed: Bool = false, releaseArmed: Bool = false, enteringReplacement: Bool = false,
                failure: LicenseActivationFailure? = nil, copiedAnnouncement: String? = nil, purchaseEmphasis: Bool = false,
                reduceMotion: Bool = false) {
        self.phase = phase
        self.draft = draft
        self.facts = facts
        self.revealed = revealed
        self.releaseArmed = releaseArmed
        self.enteringReplacement = enteringReplacement
        self.failure = failure
        self.copiedAnnouncement = copiedAnnouncement
        self.purchaseEmphasis = purchaseEmphasis
        self.reduceMotion = reduceMotion
    }

    public var description: String {
        "LicenseActivationState(phase: \(phase.rawValue), draft: \(draft), stored: \(facts.storedKey), revealed: \(revealed), armed: \(releaseArmed))"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["phase": phase.rawValue, "revealed": revealed], displayStyle: .struct) }
}

public enum LicenseActivationEvent: Equatable, Sendable {
    case replaceFacts(LicenseCardFacts)
    case editDraft(String)
    case activate
    case activationFinished(LicenseCardFacts, message: String?)
    case armRelease
    case cancelRelease
    case confirmRelease
    case releaseFinished(LicenseCardFacts, message: String?)
    case reveal
    case conceal
    case copyKey
    case purchase
    case dismissError
    case dismissCopied
    case beginReplacement
    case cancelReplacement
    case setReduceMotion(Bool)
}

public enum LicenseActivationEffect: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case activateOnThisMac(LicenseKeyDraft)
    case releaseThisMac
    case copyKey(LicenseKeyDraft)
    case showPurchaseNote

    public var description: String {
        switch self {
        case .activateOnThisMac: "activateOnThisMac(redacted)"
        case .releaseThisMac: "releaseThisMac"
        case .copyKey: "copyKey(redacted)"
        case .showPurchaseNote: "showPurchaseNote"
        }
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["effect": description], displayStyle: .enum) }
}

/// The license server paths that already exist. Purchase and copy are not endpoints.
public enum LicenseActivationEndpoint: String, Equatable, Sendable, CaseIterable {
    case activate = "api/v1/activate"
    case deactivate = "api/v1/deactivate"
    case revocations = "api/v1/revocations"
}

public enum LicenseActivationMachine {
    public static let purchaseNote = "A one-time purchase. Two Macs. The key is emailed to you after purchase."
    public static let copiedAnnouncement = "License key copied"
    public static let reentryMessage = "Save the license server address again in the License server section first. Zeus keeps its license key on this Mac until you do, so no seat is left held on the server."

    public static func restingPhase(for status: LicenseStatus) -> LicenseActivationPhase {
        switch status {
        case .trial: .trial
        case .licensed: .active
        case .trialEnded, .expired, .revoked: .unlicensed
        }
    }

    public static func endpoint(for effect: LicenseActivationEffect) -> LicenseActivationEndpoint? {
        switch effect {
        case .activateOnThisMac: .activate
        case .releaseThisMac: .deactivate
        case .copyKey, .showPurchaseNote: nil
        }
    }

    public static func initial(facts: LicenseCardFacts, reduceMotion: Bool) -> LicenseActivationState {
        var state = LicenseActivationState(phase: restingPhase(for: facts.status), facts: facts, reduceMotion: reduceMotion)
        if let message = facts.deactivationError, !LicenseKeyPrivacy.compact(message).isEmpty {
            state.failure = LicenseActivationFailure(
                message: LicenseKeyPrivacy.scrub(message, secrets: secrets(in: state)),
                resume: state.phase
            )
            state.phase = .error
        }
        return state
    }

    public static func step(_ state: LicenseActivationState, _ event: LicenseActivationEvent) -> (LicenseActivationState, [LicenseActivationEffect]) {
        var next = state
        let effects = apply(&next, event)
        return (next, effects)
    }
}

private extension LicenseActivationMachine {
    static func apply(_ state: inout LicenseActivationState, _ event: LicenseActivationEvent) -> [LicenseActivationEffect] {
        switch event {
        case .setReduceMotion(let enabled):
            state.reduceMotion = enabled
            return []
        case .replaceFacts(let facts):
            let inFlight = isInFlight(state.phase)
            let wasError = state.phase == .error
            state.facts = facts
            if inFlight { return [] }
            if facts.storedKey.isEmpty {
                state.revealed = false
                state.releaseArmed = false
                state.enteringReplacement = false
            }
            if wasError { return [] }
            if let message = facts.deactivationError, !LicenseKeyPrivacy.compact(message).isEmpty {
                state.failure = LicenseActivationFailure(message: LicenseKeyPrivacy.scrub(message, secrets: secrets(in: state)), resume: restingPhase(for: facts.status))
                state.phase = .error
            } else {
                state.phase = restingPhase(for: facts.status)
            }
            return []
        case .editDraft(let text):
            guard !isInFlight(state.phase) else { return [] }
            state.draft = LicenseKeyDraft(text)
            state.releaseArmed = false
            state.copiedAnnouncement = nil
            return []
        case .activate:
            return beginActivate(&state)
        case .activationFinished(let facts, let message):
            guard state.phase == .activating else { return [] }
            state.facts = facts
            state.revealed = false
            state.releaseArmed = false
            state.enteringReplacement = false
            state.copiedAnnouncement = nil
            if let message {
                state.failure = LicenseActivationFailure(message: LicenseKeyPrivacy.scrub(message, secrets: secrets(in: state)), resume: restingPhase(for: facts.status))
                state.phase = .error
            } else {
                state.draft = LicenseKeyDraft()
                state.failure = nil
                state.phase = restingPhase(for: facts.status)
            }
            return []
        case .armRelease:
            guard !isInFlight(state.phase), !state.facts.storedKey.isEmpty else { return [] }
            state.releaseArmed = true
            return []
        case .cancelRelease:
            guard !isInFlight(state.phase) else { return [] }
            state.releaseArmed = false
            return []
        case .confirmRelease:
            guard !isInFlight(state.phase), state.releaseArmed, !state.facts.storedKey.isEmpty else { return [] }
            state.phase = .releasing
            state.releaseArmed = false
            state.revealed = false
            state.copiedAnnouncement = nil
            return [.releaseThisMac]
        case .releaseFinished(let facts, let message):
            guard state.phase == .releasing else { return [] }
            state.facts = facts
            state.revealed = false
            state.releaseArmed = false
            state.enteringReplacement = false
            state.draft = LicenseKeyDraft()
            state.copiedAnnouncement = nil
            if let message {
                state.failure = LicenseActivationFailure(message: LicenseKeyPrivacy.scrub(message, secrets: secrets(in: state)), resume: restingPhase(for: facts.status))
                state.phase = .error
            } else {
                state.failure = nil
                state.phase = restingPhase(for: facts.status)
            }
            return []
        case .reveal:
            guard !isInFlight(state.phase), !state.facts.storedKey.isEmpty else { return [] }
            state.revealed = true
            return []
        case .conceal:
            state.revealed = false
            return []
        case .copyKey:
            guard !isInFlight(state.phase), !state.facts.storedKey.isEmpty else { return [] }
            state.copiedAnnouncement = copiedAnnouncement
            return [.copyKey(state.facts.storedKey)]
        case .purchase:
            guard state.phase == .trial || state.phase == .unlicensed else { return [] }
            state.purchaseEmphasis = true
            state.copiedAnnouncement = nil
            return [.showPurchaseNote]
        case .dismissError:
            guard state.phase == .error else { return [] }
            state.phase = state.failure?.resume ?? restingPhase(for: state.facts.status)
            state.failure = nil
            return []
        case .dismissCopied:
            state.copiedAnnouncement = nil
            return []
        case .beginReplacement:
            guard state.phase == .active else { return [] }
            state.enteringReplacement = true
            state.draft = LicenseKeyDraft()
            state.releaseArmed = false
            state.revealed = false
            state.copiedAnnouncement = nil
            return []
        case .cancelReplacement:
            guard !isInFlight(state.phase) else { return [] }
            state.enteringReplacement = false
            state.draft = LicenseKeyDraft()
            return []
        }
    }

    static func beginActivate(_ state: inout LicenseActivationState) -> [LicenseActivationEffect] {
        guard !isInFlight(state.phase) else { return [] }
        let key = state.draft.normalized
        guard !key.isEmpty else { return [] }
        let replacingActive = state.phase == .active || (state.phase == .error && state.failure?.resume == .active)
        if replacingActive, !state.enteringReplacement { return [] }
        if state.facts.serverNeedsReentry {
            state.failure = LicenseActivationFailure(message: reentryMessage, resume: restingPhase(for: state.facts.status))
            state.phase = .error
            state.releaseArmed = false
            state.copiedAnnouncement = nil
            return []
        }
        state.phase = .activating
        state.revealed = false
        state.releaseArmed = false
        state.failure = nil
        state.copiedAnnouncement = nil
        state.draft = LicenseKeyDraft(key)
        return [.activateOnThisMac(LicenseKeyDraft(key))]
    }

    static func isInFlight(_ phase: LicenseActivationPhase) -> Bool { phase == .activating || phase == .releasing }

    static func secrets(in state: LicenseActivationState) -> [String] {
        [state.draft.reveal(), state.draft.normalized, state.facts.storedKey.reveal(), state.facts.storedKey.normalized]
    }
}
