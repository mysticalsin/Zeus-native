/// The pure launch rule for the step-zero probe.
///
/// `decide` reads nothing. The caller supplies the arguments after the executable, the marker,
/// the expiry, the clock, the seal, the process facts, and the session. A fact that was not
/// read refuses. Without the one flag the answer is `notRequested` and the other facts are ignored.
///
/// This file does not look up a responsible pid, check a signature, write a report, or exit.
/// A refusal tells the caller to exit with `refusalExitCode`.
public enum StepZeroGate {
    /// The only launch argument that asks for the probe.
    public static let flag = "--step-zero-probe"

    /// A launch service name must begin with this. The trailing dot is part of the prefix.
    public static let servicePrefix = "application.app.zeus.mac."

    /// The parent pid of a process that launchd started.
    public static let launchdParent: Int32 = 1

    /// A marked build answers the flag for at most this many seconds.
    public static let maximumLife: Int64 = 72 * 60 * 60

    /// The process exit for a refusal. `decide` does not exit.
    public static let refusalExitCode: Int32 = 64

    /// What the caller was able to read about the static signature check.
    public enum Seal: Equatable, Sendable {
        case intact
        case broken
        case unread
    }

    /// Why the flag was present and the probe must not run.
    public enum Refusal: Equatable, Sendable {
        case extraArgument
        case markerMissing
        case markerUnreadable
        case expiryUnreadable
        case expiryPast
        case expiryTooFar
        case sealBroken
        case sealUnreadable
        case responsiblePIDUnreadable
        case responsiblePIDDiffers
        case parentUnreadable
        case parentNotLaunchd
        case serviceNameUnreadable
        case serviceNameOther
        case otherZeusUnreadable
        case otherZeus
        case qaUnreadable
        case qaStart
        case consoleUnreadable
        case offConsole
        case lockUnreadable
        case locked
    }

    public enum Decision: Equatable, Sendable {
        case notRequested
        case refused(Refusal)
        case run
    }

    /// Facts already read by the caller. Nil means that read failed.
    ///
    /// `otherZeus` counts Zeus processes other than this one. `qaStart` is the startup
    /// policy, not a second argument: a second argument is refused before the session is read.
    public struct Facts: Equatable, Sendable {
        public var arguments: [String]
        public var marker: Bool?
        public var expiry: Int64?
        public var now: Int64
        public var seal: Seal
        public var responsiblePID: Int32?
        public var ownPID: Int32
        public var parentPID: Int32?
        public var serviceName: String?
        public var otherZeus: Int?
        public var qaStart: Bool?
        public var onConsole: Bool?
        public var unlocked: Bool?

        public init(
            arguments: [String],
            marker: Bool?,
            expiry: Int64?,
            now: Int64,
            seal: Seal,
            responsiblePID: Int32?,
            ownPID: Int32,
            parentPID: Int32?,
            serviceName: String?,
            otherZeus: Int?,
            qaStart: Bool?,
            onConsole: Bool?,
            unlocked: Bool?
        ) {
            self.arguments = arguments
            self.marker = marker
            self.expiry = expiry
            self.now = now
            self.seal = seal
            self.responsiblePID = responsiblePID
            self.ownPID = ownPID
            self.parentPID = parentPID
            self.serviceName = serviceName
            self.otherZeus = otherZeus
            self.qaStart = qaStart
            self.onConsole = onConsole
            self.unlocked = unlocked
        }
    }

    public static func decide(_ facts: Facts) -> Decision {
        let hits = facts.arguments.reduce(into: 0) { count, argument in
            if argument == flag { count += 1 }
        }
        if hits == 0 { return .notRequested }
        guard facts.arguments == [flag] else { return .refused(.extraArgument) }

        guard let marker = facts.marker else { return .refused(.markerUnreadable) }
        guard marker else { return .refused(.markerMissing) }

        guard let expiry = facts.expiry else { return .refused(.expiryUnreadable) }
        let (life, overflow) = expiry.subtractingReportingOverflow(facts.now)
        if overflow { return .refused(.expiryUnreadable) }
        if life <= 0 { return .refused(.expiryPast) }
        if life > maximumLife { return .refused(.expiryTooFar) }

        switch facts.seal {
        case .intact:
            break
        case .broken:
            return .refused(.sealBroken)
        case .unread:
            return .refused(.sealUnreadable)
        }

        guard let responsible = facts.responsiblePID else { return .refused(.responsiblePIDUnreadable) }
        guard responsible == facts.ownPID else { return .refused(.responsiblePIDDiffers) }

        guard let parent = facts.parentPID else { return .refused(.parentUnreadable) }
        guard parent == launchdParent else { return .refused(.parentNotLaunchd) }

        guard let service = facts.serviceName, !service.isEmpty else {
            return .refused(.serviceNameUnreadable)
        }
        guard service.hasPrefix(servicePrefix) else { return .refused(.serviceNameOther) }

        guard let others = facts.otherZeus, others >= 0 else { return .refused(.otherZeusUnreadable) }
        guard others == 0 else { return .refused(.otherZeus) }

        guard let qa = facts.qaStart else { return .refused(.qaUnreadable) }
        if qa { return .refused(.qaStart) }

        guard let onConsole = facts.onConsole else { return .refused(.consoleUnreadable) }
        guard onConsole else { return .refused(.offConsole) }

        guard let unlocked = facts.unlocked else { return .refused(.lockUnreadable) }
        guard unlocked else { return .refused(.locked) }

        return .run
    }
}
