import Foundation

/// Shared values for the lock-screen surface. The reducer and the layout live beside this file.
/// No window is created here, and no session is read.

/// Why the surface cannot be armed.
public enum LockUnavailable: Equatable, Sendable {
    /// One or more space symbols were missing. The names are the ones the loader reported.
    case missingSymbols([String])
    /// The running major version is outside the versions checked on a Mac.
    case untestedSystem(Int)
}

/// Why a surface that had been armed is staying down.
public enum LockStop: Equatable, Sendable {
    /// A marker from this boot, or a marker whose boot id could not be read.
    case problemLastTime
    /// A marker from a different boot. The Mac went down with the window up.
    case restartLastTime
    /// A space or window step failed. `step` is the name the controller reported.
    case callFailed(step: String)
}

/// The file the controller writes before a window opens, and keeps when a step fails.
public struct LockMarker: Equatable, Sendable {
    public var bootID: String
    public var osBuild: String
    public var failedStep: String?

    public init(bootID: String, osBuild: String, failedStep: String?) {
        self.bootID = bootID
        self.osBuild = osBuild
        self.failedStep = failedStep
    }
}

/// The status row. `word` is the whole sentence a person reads. `symbol` is the warning glyph name.
public struct LockStatus: Equatable, Sendable {
    public var word: String
    public var symbol: String
    public var canTurnOnAgain: Bool

    public init(word: String, symbol: String, canTurnOnAgain: Bool) {
        self.word = word
        self.symbol = symbol
        self.canTurnOnAgain = canTurnOnAgain
    }
}

/// What the controller copies from a session reading. `lockSurfaceMayShow` is that reading's own flag.
/// An unreadable session arrives as false, so the surface stays down.
public struct LockPresenceInput: Equatable, Sendable {
    public var lockSurfaceMayShow: Bool

    public init(lockSurfaceMayShow: Bool) {
        self.lockSurfaceMayShow = lockSurfaceMayShow
    }
}

/// Major versions whose space calls have been checked. 14, 15 and anything past 27 stay unavailable.
public enum LockSupport {
    public static let checkedMajors: Set<Int> = [26, 27]
}

public enum LockStatusText {
    public static let unavailable = "Not available on this macOS"
    public static let problem = "Stopped after a problem"
    public static let restart = "Stopped after a restart"
    public static let symbol = "exclamationmark.triangle"

    /// Nil while the switch already says the feature is off or running. A problem is a word and a symbol.
    public static func status(for phase: LockSurface.Phase) -> LockStatus? {
        switch phase {
        case .unavailable:
            return LockStatus(word: unavailable, symbol: symbol, canTurnOnAgain: false)
        case .stopped(.restartLastTime):
            return LockStatus(word: restart, symbol: symbol, canTurnOnAgain: true)
        case .stopped:
            return LockStatus(word: problem, symbol: symbol, canTurnOnAgain: true)
        case .off, .ready, .opening, .open, .closing:
            return nil
        }
    }
}

/// The settings card talks to this. The window controller is the live conformer, and it can arrive later.
@MainActor
public protocol LockScreenControlling: AnyObject {
    var status: LockStatus? { get }
    func turnOnAgain()
}
