import Foundation

/// Shared values for the macOS Focus name. Pure and `Sendable`, so the store rules, the machine
/// and the notch compile apart and meet only here. This file reads no Focus store and asks for
/// no permission.

public struct SystemFocusMode: Equatable, Sendable {
    public var id: String?
    public var name: String?
    public var symbol: String?

    public init(id: String? = nil, name: String? = nil, symbol: String? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
    }
}

public enum SystemFocusReading: Equatable, Sendable {
    case unknown
    case off
    case on(SystemFocusMode)
}

/// One store file as `fstat` reports it: inode, size, and modification time.
public struct SystemFocusStamp: Equatable, Sendable {
    public var inode: UInt64
    public var size: Int64
    public var seconds: Int64
    public var nanoseconds: Int32

    public init(inode: UInt64, size: Int64, seconds: Int64, nanoseconds: Int32) {
        self.inode = inode
        self.size = size
        self.seconds = seconds
        self.nanoseconds = nanoseconds
    }
}

/// One optional stamp for each Focus store file.
public struct SystemFocusStamps: Equatable, Sendable {
    public var assertions: SystemFocusStamp?
    public var configurations: SystemFocusStamp?

    public init(assertions: SystemFocusStamp? = nil, configurations: SystemFocusStamp? = nil) {
        self.assertions = assertions
        self.configurations = configurations
    }
}

public enum SystemFocusStoreRead: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// The bytes are not the expected JSON object.
        case malformed
        /// A file is larger than the read cap.
        case tooLarge
        /// The path is not a regular file, or the folder path is not a directory.
        case notAFile
        /// The read was refused even though Full Disk Access is granted.
        case refused
        case other
    }

    case ok(SystemFocusReading)
    /// The stamps match the last finished read, so the bytes were left unread.
    case unchanged
    /// Full Disk Access is missing.
    case denied
    /// The Focus store folder is absent.
    case missing
    case unreadable(Reason)
}

public enum SystemFocusShown: Equatable, Sendable {
    case none
    case on(label: String, symbol: String)
}

public struct SystemFocusCue: Equatable, Sendable {
    public var label: String
    public var symbol: String
    public var on: Bool

    public init(label: String, symbol: String, on: Bool) {
        self.label = label
        self.symbol = symbol
        self.on = on
    }
}

public enum SystemFocusRowStatus: Equatable, Sendable {
    case off
    case checking
    case allowed
    case needsAccess
    case unavailable
}

public struct SystemFocusSurface: Equatable, Sendable {
    public var shown: SystemFocusShown
    public var row: SystemFocusRowStatus

    public init(shown: SystemFocusShown, row: SystemFocusRowStatus) {
        self.shown = shown
        self.row = row
    }

    /// The fixture a snapshot draws. A snapshot does not start a Focus read.
    public static let snapshotSample = SystemFocusSurface(
        shown: .on(label: "Work", symbol: "moon.fill"),
        row: .allowed
    )
}

/// The public Focus-status answer the routine card and the morning brief already use.
public enum SystemFocusPublic {
    /// True only when the status is authorized and the system reports a Focus is on.
    /// A missing report is not on.
    public static func quiet(authorized: Bool, isFocused: Bool?) -> Bool {
        authorized && isFocused == true
    }
}

/// What the Settings row and the notch use to drive the Focus name. Main-actor isolated so a
/// main-actor controller and a main-actor test fake can both conform.
@MainActor
public protocol SystemFocusControlling: AnyObject {
    var surface: SystemFocusSurface { get }
    func setEnabled(_ on: Bool)
    func recheck()
    func openSettingsPane()
}
