// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): SessionAutoLocker.swift, LockMonitor.swift.
import Foundation

/// The choices for "Lock after absent for", and the one label to seconds rule.
public enum FaceLockAfter {
    public struct Choice: Equatable, Sendable {
        public let label: String
        public let seconds: Double
    }

    public static let choices: [Choice] = [
        Choice(label: "30 seconds", seconds: 30),
        Choice(label: "1 minute", seconds: 60),
        Choice(label: "2 minutes", seconds: 120),
        Choice(label: "5 minutes", seconds: 300),
        Choice(label: "10 minutes", seconds: 600),
    ]
    public static let defaultLabel = "2 minutes"
    public static let defaultSeconds: Double = 120

    /// Seconds for a stored label. An unknown label is two minutes, never zero.
    public static func seconds(forLabel label: String) -> Double {
        choices.first { $0.label == label }?.seconds ?? defaultSeconds
    }

    static func isChoice(_ seconds: Double) -> Bool {
        seconds.isFinite && choices.contains { $0.seconds == seconds }
    }
}

/// The one reducer behind face presence. A Sendable value: `handle` takes an event and returns the effects the
/// controller must carry out. No clock inside: time arrives in events as `uptime` (`ProcessInfo.systemUptime`,
/// monotonic), and every rule compares timestamps, never counts ticks, so a wall clock change cannot shorten a
/// countdown and a long stall is read correctly when the next frame arrives.
///
/// The camera runs only while `wantsCamera`. Launch, an import or another feature cannot reach those states: only
/// the owner's switch, the owner's Enroll tap and an unlock after the owner switched it on can. Nothing here
/// unlocks anything; the only outward effect that touches the Mac is `lockNow`, asked for once.
public struct FacePresenceMachine: Equatable, Sendable {
    /// Seconds of a missed frame that a present owner is allowed before reading as away.
    public static let absentGrace: Double = 3
    /// Seconds of watching with no frame at all before the camera is called unavailable.
    public static let stallLimit: Double = 10
    public static let defaultLockAfter: Double = FaceLockAfter.defaultSeconds

    public enum PauseReason: Equatable, Sendable {
        case launch, screenLocked, asleep, lockedByZeus, noFace, zeusCapture
    }

    public enum UnavailableReason: Equatable, Sendable {
        case camera, lock, vault
    }

    public enum State: Equatable, Sendable {
        case off
        case needsCameraConsent
        /// The switch is on and there is no face yet. Enrollment waits for a second, explicit confirm.
        case needsEnrollmentConfirm
        case enrolling(token: Int)
        case watching(since: Double)
        case present(lastSeen: Double)
        case away(since: Double)
        case paused(PauseReason)
        case unavailable(UnavailableReason)
    }

    /// What other features may read, and the only thing they may read.
    public enum Presence: Equatable, Sendable {
        case present, absent, unknown
    }

    public enum CameraAccess: Equatable, Sendable {
        case notDetermined, authorized
        /// Denied or restricted.
        case denied
    }

    /// What the system's session dictionary said. Only `unlocked` starts anything.
    public enum SessionLockState: Equatable, Sendable {
        case unlocked, locked, unknown
    }

    public enum Event: Equatable, Sendable {
        case launch(storedOn: Bool)
        case switchOn(camera: CameraAccess, enabledFaces: Int, canLock: Bool, vaultReadable: Bool, uptime: Double)
        case switchOff
        case consentAnswered(granted: Bool, enabledFaces: Int, uptime: Double)
        case enroll
        /// `saved` is for the log; the next state reads `enabledFaces`.
        case enrollmentEnded(token: Int, saved: Bool, enabledFaces: Int, uptime: Double)
        case facesChanged(enabledFaces: Int, uptime: Double)
        case setLockAfter(seconds: Double)
        case cameraFailed
        case cameraReturned(uptime: Double)
        case observed(FacePresenceVerdict, uptime: Double)
        case tick(uptime: Double)
        case screenLocked
        case screenUnlocked(uptime: Double, session: SessionLockState)
        case willSleep
        case didWake(uptime: Double, session: SessionLockState)
        case zeusCapture(active: Bool, uptime: Double)
        case lockFinished(ok: Bool)
    }

    public enum Effect: Equatable, Sendable {
        case askCameraConsent
        case openCameraSettings
        case beginEnrollment(token: Int)
        case cancelEnrollment(token: Int)
        case lockNow
    }

    public private(set) var state: State = .off
    /// Whether the owner's switch is on. A launch with the switch on is on, paused.
    public private(set) var switchOn = false
    public private(set) var lockAfter: Double = FacePresenceMachine.defaultLockAfter
    /// How many enabled faces there are, as last told. Read when a pause ends.
    public private(set) var enabledFaces = 0
    /// True while the teleprompter (or any other Zeus capture) holds the camera, whatever state this is in.
    public private(set) var zeusCaptureActive = false
    private var lastToken = 0

    public init() {}

    // MARK: Derived

    /// True only for `enrolling`, `watching`, `present` and `away`. The controller keeps the camera in step with it.
    public var wantsCamera: Bool {
        switch state {
        case .enrolling, .watching, .present, .away: return true
        case .off, .needsCameraConsent, .needsEnrollmentConfirm, .paused, .unavailable: return false
        }
    }

    /// True only for `watching`, `present` and `away`: the one second timer runs while it is.
    public var wantsTicks: Bool {
        switch state {
        case .watching, .present, .away: return true
        case .off, .needsCameraConsent, .needsEnrollmentConfirm, .enrolling, .paused, .unavailable: return false
        }
    }

    /// Enroll can be tapped while watching, present or away, and for the second confirm when no face is saved yet.
    public var canEnroll: Bool {
        switch state {
        case .needsEnrollmentConfirm, .watching, .present, .away: return true
        case .off, .needsCameraConsent, .enrolling, .paused, .unavailable: return false
        }
    }

    public var presence: Presence {
        switch state {
        case .present: return .present
        case .away: return .absent
        default: return .unknown
        }
    }

    /// Seconds until the lock while away, never below zero. Nil in every other state.
    public func countdown(at uptime: Double) -> Double? {
        guard case .away(let since) = state else { return nil }
        return max(0, lockAfter - (uptime - since))
    }

    public func status(at uptime: Double) -> FacePresenceStatus {
        FacePresenceStatus.make(state: state, lockAfter: lockAfter, uptime: uptime)
    }

    // MARK: Events

    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .launch(let storedOn):
            switchOn = storedOn
            return move(to: storedOn ? .paused(.launch) : .off)

        case .switchOn(let camera, let faces, let canLock, let vaultReadable, let uptime):
            switch state {
            case .off, .unavailable: break
            default: return []
            }
            switchOn = true
            enabledFaces = faces
            guard canLock else { return move(to: .unavailable(.lock)) }
            guard vaultReadable else { return move(to: .unavailable(.vault)) }
            switch camera {
            case .notDetermined: return move(to: .needsCameraConsent, [.askCameraConsent])
            case .denied: return move(to: .needsCameraConsent, [.openCameraSettings])
            case .authorized: return begin(at: uptime)
            }

        case .switchOff:
            switchOn = false
            return move(to: .off)

        case .consentAnswered(let granted, let faces, let uptime):
            guard state == .needsCameraConsent else { return [] }
            enabledFaces = faces
            return granted ? begin(at: uptime) : []

        case .enroll:
            return canEnroll ? startEnrolling() : []

        case .enrollmentEnded(let token, _, let faces, let uptime):
            guard case .enrolling(let current) = state, current == token else { return [] }
            enabledFaces = faces
            // The enrollment is over, so there is nothing left to cancel.
            return move(to: faces > 0 ? resumeState(at: uptime) : .paused(.noFace), cancelsEnrollment: false)

        case .facesChanged(let faces, let uptime):
            enabledFaces = faces
            switch state {
            case .watching, .present, .away:
                return faces == 0 ? move(to: .paused(.noFace)) : []
            case .paused(.noFace):
                return faces > 0 ? move(to: resumeState(at: uptime)) : []
            default:
                return []
            }

        case .setLockAfter(let seconds):
            lockAfter = FaceLockAfter.isChoice(seconds) ? seconds : Self.defaultLockAfter
            return []

        case .cameraFailed:
            guard wantsCamera else { return [] }
            return move(to: .unavailable(.camera))

        case .cameraReturned(let uptime):
            guard state == .unavailable(.camera) else { return [] }
            return move(to: resumeState(at: uptime))

        case .observed(let verdict, let uptime):
            guard uptime.isFinite else { return [] }
            return observe(verdict, at: uptime)

        case .tick(let uptime):
            guard uptime.isFinite else { return [] }
            return tick(at: uptime)

        case .screenLocked:
            return pauseForLockOrSleep(.screenLocked)

        case .willSleep:
            return pauseForLockOrSleep(.asleep)

        case .screenUnlocked(let uptime, let session):
            guard session == .unlocked, uptime.isFinite else { return [] }
            switch state {
            case .paused(let reason) where Self.endsWithUnlock(reason): return move(to: resumeState(at: uptime))
            case .unavailable(.camera): return move(to: resumeState(at: uptime))
            default: return []
            }

        case .didWake(let uptime, let session):
            guard session == .unlocked, uptime.isFinite else { return [] }
            switch state {
            case .paused(let reason) where Self.endsWithUnlock(reason): return move(to: resumeState(at: uptime))
            default: return []
            }

        case .zeusCapture(let active, let uptime):
            zeusCaptureActive = active
            if active {
                return wantsCamera ? move(to: .paused(.zeusCapture)) : []
            }
            guard state == .paused(.zeusCapture), uptime.isFinite else { return [] }
            return move(to: resumeState(at: uptime))

        case .lockFinished(let ok):
            guard state == .paused(.lockedByZeus), !ok else { return [] }
            return move(to: .unavailable(.lock))
        }
    }

    // MARK: Rules

    private static func endsWithUnlock(_ reason: PauseReason) -> Bool {
        switch reason {
        case .launch, .screenLocked, .asleep, .lockedByZeus: return true
        case .noFace, .zeusCapture: return false
        }
    }

    /// Where a stopped feature goes when it may run again: held by a Zeus capture, waiting for a face, or watching.
    private func resumeState(at uptime: Double) -> State {
        if zeusCaptureActive { return .paused(.zeusCapture) }
        if enabledFaces == 0 { return .paused(.noFace) }
        return .watching(since: uptime)
    }

    /// Start from a granted camera: enroll when there is no face, else watch. A running Zeus capture holds it off.
    private mutating func begin(at uptime: Double) -> [Effect] {
        if zeusCaptureActive { return move(to: .paused(.zeusCapture)) }
        if enabledFaces == 0 { return move(to: .needsEnrollmentConfirm) }
        return move(to: .watching(since: uptime))
    }

    private mutating func startEnrolling() -> [Effect] {
        lastToken += 1
        return move(to: .enrolling(token: lastToken), [.beginEnrollment(token: lastToken)])
    }

    private mutating func pauseForLockOrSleep(_ reason: PauseReason) -> [Effect] {
        switch state {
        case .watching, .present, .away, .enrolling, .needsEnrollmentConfirm:
            // A pending enrollment confirm is not an enrollment yet, so there is no token to cancel.
            // Leaving the confirm state is what drops it.
            return move(to: .paused(reason))
        case .paused(.lockedByZeus) where reason == .screenLocked:
            // The lock Zeus asked for arrives as a lock notice: keep saying so.
            return []
        case .paused:
            return move(to: .paused(reason))
        case .off, .needsCameraConsent, .unavailable:
            return []
        }
    }

    private mutating func observe(_ verdict: FacePresenceVerdict, at uptime: Double) -> [Effect] {
        switch (state, verdict) {
        case (.watching, .owner):
            return move(to: .present(lastSeen: uptime))
        case (.watching(let since), .notOwner):
            return awayOrLock(since: since, at: uptime)
        case (.present(let last), .owner):
            return move(to: .present(lastSeen: max(last, uptime)))
        case (.present(let last), .notOwner):
            guard uptime - last >= Self.absentGrace else { return [] }
            return awayOrLock(since: last, at: uptime)
        case (.away, .owner):
            return move(to: .present(lastSeen: uptime))
        case (.away(let since), .notOwner):
            return lockIfDue(since: since, at: uptime)
        default:
            // A frame that raced a stop, or one for an enrollment the plan reads: dropped.
            return []
        }
    }

    private mutating func tick(at uptime: Double) -> [Effect] {
        switch state {
        case .watching(let since):
            return uptime - since >= Self.stallLimit ? move(to: .unavailable(.camera)) : []
        case .present(let last):
            guard uptime - last >= Self.absentGrace else { return [] }
            return awayOrLock(since: last, at: uptime)
        case .away(let since):
            return lockIfDue(since: since, at: uptime)
        default:
            return []
        }
    }

    /// Becomes away since `since`, and locks at once when the limit has already passed (a long stall).
    private mutating func awayOrLock(since: Double, at uptime: Double) -> [Effect] {
        _ = move(to: .away(since: since))
        return lockIfDue(since: since, at: uptime)
    }

    /// The lock is asked for once: the state leaves `away` in the same step, so no later tick can ask again.
    private mutating func lockIfDue(since: Double, at uptime: Double) -> [Effect] {
        guard uptime - since >= lockAfter else { return [] }
        return move(to: .paused(.lockedByZeus), [.lockNow])
    }

    /// Changes state. Leaving an enrollment for any reason but its own end cancels it, so no path can leave the
    /// enrollment, and the camera it holds, running.
    private mutating func move(to new: State, _ effects: [Effect] = [], cancelsEnrollment: Bool = true) -> [Effect] {
        var result: [Effect] = []
        if cancelsEnrollment, case .enrolling(let token) = state, new != state {
            result.append(.cancelEnrollment(token: token))
        }
        state = new
        return result + effects
    }
}

extension FacePresenceMachine.State {
    /// A plain name for the log: the state and its reason, never a time or a token. Logs carry names and counts only.
    public var logName: String {
        switch self {
        case .off: return "off"
        case .needsCameraConsent: return "needsCameraConsent"
        case .needsEnrollmentConfirm: return "needsEnrollmentConfirm"
        case .enrolling: return "enrolling"
        case .watching: return "watching"
        case .present: return "present"
        case .away: return "away"
        case .paused(let reason): return "paused(\(reason))"
        case .unavailable(let reason): return "unavailable(\(reason))"
        }
    }
}
