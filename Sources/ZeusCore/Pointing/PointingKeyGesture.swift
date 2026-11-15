import Foundation

/// The pointing talk key. Pure: feed it the keyboard stream, it says when a hold began, ended,
/// or was spoiled. It owns no monitor, so the same logic serves a CGEvent tap and the tests.
///
/// It reads the keyboard through `KeyFacts`, as the voice key machine does, so one rule decides what is a clean press,
/// a release and a larger chord (docs/VOICE-KEY-MACHINE-PLAN.md, 4.5). Rules: the chord starts the moment it is held
/// exactly, or after `confirm` when a tiling chord holds the key's modifiers. Any other key or modifier joining
/// cancels the turn (the "spoil" rule), so Control+Option+Space (Chat) and other chords that
/// share the modifiers keep working. Nothing starts again until every key is up, and the wait begins as soon as the
/// key's own set is down with something foreign, even before a hold began.
public struct PointingKeyGesture: Sendable, Equatable {
    public enum Output: Equatable, Sendable {
        /// An exact hold waits for its confirm. The owner asks for `confirmElapsed` after `confirm` seconds.
        case armed
        case began
        case ended
        case cancelled
        /// Esc with no modifiers while no hold is active (interrupts speech).
        case escape
        /// Two quick lone Control taps. Detected only; Phase 1 does not act on it.
        case doubleTapControl
        /// The hold never reported a release: the live modifiers say the keys are up, or `maxHold` passed.
        /// The gesture has already resynced; the turn should end as if the keys were released.
        case holdTimedOut
    }

    public static let tapMaximum: TimeInterval = 0.30
    public static let doubleTapWindow: TimeInterval = 0.40
    /// A hold longer than this is a stuck modifier (the microphone stops at 90 s anyway).
    public static let maxHold: TimeInterval = 95
    /// A wake may arrive this much early: the clock that schedules it and the clock that stamps events differ.
    private static let slack: TimeInterval = 0.001

    public var shortcut: Shortcut
    /// How long an exact hold waits before it begins: 0 except while a tiling chord holds the key's modifiers.
    public var confirm: TimeInterval = 0
    public private(set) var isActive = false
    /// True while the chord is held but unusable (Control+Option with VoiceOver on).
    public private(set) var blockedByVoiceOver = false
    // Read by the walk of every press order (Tests/ZeusCoreTests/VoiceKeyWalkTests.swift) to key its states.
    private(set) var state = ShortcutState()
    private(set) var waitForRelease = false
    private(set) var activeSince: TimeInterval?
    /// An exact hold that has not begun yet, since when.
    private(set) var armedSince: TimeInterval?
    private var controlDownAt: TimeInterval?
    private var controlTapClean = false
    private var lastControlTap: TimeInterval?

    public init(shortcut: Shortcut = .controlOption) { self.shortcut = shortcut }

    /// Whether an exact hold is waiting for its confirm.
    public var isArmed: Bool { armedSince != nil }

    public mutating func feed(_ event: ShortcutEvent, at time: TimeInterval, voiceOverOn: Bool = false) -> Output? {
        state.apply(event)
        let tap = trackControlTap(event, at: time)
        let facts = KeyFacts(of: state, key: shortcut)
        let foreign = facts.foreignModifier || facts.foreignKey
        let exact = facts.ownDown && !foreign

        if isActive {
            if exact { return nil }
            isActive = false; activeSince = nil
            if !foreign { return .ended }
            waitForRelease = true
            return .cancelled
        }
        if armedSince != nil {
            if exact { return nil }
            armedSince = nil
            if foreign { waitForRelease = true }
            return nil
        }
        if facts.allUp {
            waitForRelease = false
        } else if facts.ownDown, foreign {
            waitForRelease = true
        }
        if waitForRelease { return nil }
        if exact {
            blockedByVoiceOver = voiceOverOn && shortcut == .controlOption
            if blockedByVoiceOver { return nil }
            if confirm > 0 {
                armedSince = time
                return .armed
            }
            isActive = true
            activeSince = time
            return .began
        }
        blockedByVoiceOver = false
        if case .keyDown(53, let mods) = event, mods.isEmpty { return .escape }
        return tap
    }

    /// The confirm has passed. The hold begins if it is still exact; a live picture that no longer holds the key's
    /// modifiers means a release was missed, and nothing begins.
    public mutating func confirmElapsed(at time: TimeInterval, liveModifiers: ShortcutModifiers?) -> Output? {
        guard let since = armedSince, time - since >= confirm - Self.slack else { return nil }
        armedSince = nil
        if let live = liveModifiers, !live.isSuperset(of: shortcut.modifiers) {
            state.resync(to: live)
            return nil
        }
        isActive = true
        // The hold is counted from now, on the clock the watchdog's `tick` uses, whatever clock stamped the key events.
        activeSince = time
        return .began
    }

    public mutating func reset() { self = PointingKeyGesture(shortcut: shortcut) }

    /// Watchdog, called a few times a second while a hold is active. `liveModifiers` is what the
    /// system reports right now (nil when unknown). If they no longer include the chord, or the hold
    /// outlived `maxHold`, a release was missed: resync the tracked state and report `holdTimedOut`.
    public mutating func tick(at time: TimeInterval, liveModifiers: ShortcutModifiers?) -> Output? {
        guard isActive, let since = activeSince else { return nil }
        let released = liveModifiers.map { !$0.isSuperset(of: shortcut.modifiers) } ?? false
        guard released || time - since > Self.maxHold else { return nil }
        isActive = false; activeSince = nil
        controlDownAt = nil; controlTapClean = false
        // Until the system shows every key up, a new hold cannot start, and the wait cannot clear while a key is held.
        if let live = liveModifiers { state.resync(to: live) }
        waitForRelease = !(liveModifiers?.isEmpty ?? false)
        return .holdTimedOut
    }

    /// Sleep, wake or a display change: a hold in progress is cancelled and cannot restart until every
    /// modifier is up. Nothing is sent. Returns `.cancelled` only when a hold was active. `liveModifiers` is what the
    /// system reports now: the picture takes it, so one modifier let go and pressed again is never all up in between.
    public mutating func interrupt(liveModifiers: ShortcutModifiers? = nil) -> Output? {
        let wasActive = isActive
        isActive = false; activeSince = nil; armedSince = nil
        controlDownAt = nil; controlTapClean = false; lastControlTap = nil
        if let live = liveModifiers { state.resync(to: live) }
        waitForRelease = (wasActive || waitForRelease) && !(liveModifiers?.isEmpty ?? false)
        return wasActive ? .cancelled : nil
    }

    private mutating func trackControlTap(_ event: ShortcutEvent, at time: TimeInterval) -> Output? {
        switch event {
        case .keyDown:
            controlTapClean = false
        case .flags:
            let mods = state.modifiers
            if mods == [.control], controlDownAt == nil {
                controlDownAt = time; controlTapClean = true
            } else if mods.isEmpty, let down = controlDownAt {
                defer { controlDownAt = nil; controlTapClean = false }
                guard controlTapClean, time - down <= Self.tapMaximum else { lastControlTap = nil; return nil }
                if let last = lastControlTap, time - last <= Self.doubleTapWindow {
                    lastControlTap = nil
                    return .doubleTapControl
                }
                lastControlTap = time
            } else if mods != [.control] {
                controlTapClean = false
            }
        case .keyUp: break
        }
        return nil
    }
}
