import Foundation

/// A window in the system's on-screen list. Only its owner, bounds and level are read: never a title.
public struct TileOnScreenWindow: Equatable, Sendable {
    public var pid: Int32
    /// Bounds in engine coordinates.
    public var frame: TileRect
    /// 0 for a normal window. Menu bar items, overlays and floating panels sit on other levels.
    public var layer: Int
    public var ownerName: String?

    public init(pid: Int32, frame: TileRect, layer: Int, ownerName: String?) {
        self.pid = pid
        self.frame = frame
        self.layer = layer
        self.ownerName = ownerName
    }
}

/// What the driver managed to read about one window and its app. A nil is a property that could not be read,
/// and a window with any nil is left alone.
public struct TileWindowFacts: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String?
    public var isRegularApp: Bool?
    public var role: String?
    public var subrole: String?
    public var isMinimized: Bool?
    public var isFullScreen: Bool?
    /// Whether the window's size can be written.
    public var isSizeSettable: Bool?
    /// In engine coordinates.
    public var frame: TileRect?

    public init(pid: Int32, bundleID: String?, isRegularApp: Bool?, role: String?, subrole: String?,
                isMinimized: Bool?, isFullScreen: Bool?, isSizeSettable: Bool?, frame: TileRect?) {
        self.pid = pid
        self.bundleID = bundleID
        self.isRegularApp = isRegularApp
        self.role = role
        self.subrole = subrole
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
        self.isSizeSettable = isSizeSettable
        self.frame = frame
    }
}

/// What admission needs besides the window: who Zeus is, what the owner excluded, and the smallest window.
public struct TileAdmissionPolicy: Equatable, Sendable {
    public var zeusPID: Int32
    public var zeusBundleID: String?
    public var excludedBundleIDs: Set<String>
    public var minimumSize: Double

    public init(zeusPID: Int32, zeusBundleID: String?, excludedBundleIDs: Set<String>, minimumSize: Double) {
        self.zeusPID = zeusPID
        self.zeusBundleID = zeusBundleID
        self.excludedBundleIDs = excludedBundleIDs
        self.minimumSize = minimumSize
    }

    public init(config: TileConfig, zeusPID: Int32, zeusBundleID: String?) {
        self.init(zeusPID: zeusPID, zeusBundleID: zeusBundleID, excludedBundleIDs: config.excludedBundleIDs,
                  minimumSize: config.minTileSize)
    }
}

/// Why a window is not tiled.
public enum TileRejection: Equatable, Sendable {
    /// A property needed for the decision could not be read.
    case unreadable
    case notRegularApp
    case ownWindow
    case systemProcess
    case excludedApp
    case notStandardWindow
    case minimized
    case fullScreen
    case notResizable
    /// Not in the on-screen list: another Space, or hidden.
    case otherSpace
    case tooSmall
}

/// The admission filter. A window is tiled only when every property reads cleanly and all of them pass.
/// Everything else is ignored and never moved. Pure.
public enum TileAdmission {
    /// System processes that own windows which must never be arranged.
    public static let systemBundleIDs: Set<String> = [
        "com.apple.dock", "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.Spotlight", "com.apple.loginwindow", "com.apple.systemuiserver",
    ]
    /// The same processes by the owner name the window list reports.
    public static let systemOwnerNames: Set<String> = [
        "Dock", "Control Center", "Notification Center", "Spotlight", "loginwindow", "SystemUIServer",
    ]

    /// The checks that need only the app. The driver runs this first, so it reads no window of an app that
    /// would be refused anyway.
    public static func appRejection(pid: Int32, bundleID: String?, isRegularApp: Bool?, policy: TileAdmissionPolicy) -> TileRejection? {
        guard let bundleID, let isRegularApp else { return .unreadable }
        if pid == policy.zeusPID || bundleID == policy.zeusBundleID { return .ownWindow }
        if !isRegularApp { return .notRegularApp }
        if systemBundleIDs.contains(bundleID) { return .systemProcess }
        if policy.excludedBundleIDs.contains(bundleID) { return .excludedApp }
        return nil
    }

    /// The first reason `facts` is not tiled, or nil when it is admitted. `onScreen` is the system's list of
    /// windows on the current Space. A window is judged alone here: use `rejections` for the windows of a pass,
    /// where a frame shared by several windows is judged across all of them.
    public static func rejection(_ facts: TileWindowFacts, onScreen: [TileOnScreenWindow], policy: TileAdmissionPolicy) -> TileRejection? {
        rejections([facts], onScreen: onScreen, policy: policy)[0]
    }

    /// The answer of `rejection` for each of `windows`, in the same order, judged as one set. The window list says
    /// only that some window of the process sits at a frame, so when more windows of the process could be that
    /// entry than the list has entries for it, which of them is on this Space is unknown and every candidate among
    /// them is `.unreadable` (left alone). A candidate is a window that passes every other check. A window could be
    /// the entry when it sits at the frame, whatever else is wrong with it (a panel, a fixed-size window, one in
    /// full screen), or when its frame did not read. Only a minimized window is certainly not on screen.
    public static func rejections(_ windows: [TileWindowFacts], onScreen: [TileOnScreenWindow], policy: TileAdmissionPolicy) -> [TileRejection?] {
        let stages = windows.map { stage(of: $0, policy: policy) }
        return zip(windows, stages).map { facts, stage in
            switch stage {
            case .rejected(let reason):
                return reason
            case .candidate(let frame):
                let entries = onScreen.filter { $0.pid == facts.pid && $0.layer == 0 && TileReadBack.matches($0.frame, frame) }
                guard let match = entries.first else { return .otherSpace }
                let sharing = windows.filter { couldBeOnScreen($0, at: frame, pid: facts.pid) }.count
                if sharing > entries.count { return .unreadable }
                if let owner = match.ownerName, systemOwnerNames.contains(owner) { return .systemProcess }
                return nil
            }
        }
    }

    /// Whether `window` could be the on-screen entry of `pid` at `frame`.
    private static func couldBeOnScreen(_ window: TileWindowFacts, at frame: TileRect, pid: Int32) -> Bool {
        guard window.pid == pid, window.isMinimized != true else { return false }
        guard let own = window.frame, isReal(own) else { return true }
        return TileReadBack.matches(own, frame)
    }

    /// Everything admission decides without the window list: a rejection, or the frame to look for in it.
    private enum Stage {
        case rejected(TileRejection)
        case candidate(TileRect)
    }

    private static func stage(of facts: TileWindowFacts, policy: TileAdmissionPolicy) -> Stage {
        if let reason = appRejection(pid: facts.pid, bundleID: facts.bundleID, isRegularApp: facts.isRegularApp, policy: policy) {
            return .rejected(reason)
        }
        guard let role = facts.role, let subrole = facts.subrole, let minimized = facts.isMinimized,
              let fullScreen = facts.isFullScreen, let settable = facts.isSizeSettable, let frame = facts.frame,
              isReal(frame) else { return .rejected(.unreadable) }
        if role != "AXWindow" || subrole != "AXStandardWindow" { return .rejected(.notStandardWindow) }
        if minimized { return .rejected(.minimized) }
        if fullScreen { return .rejected(.fullScreen) }
        if !settable { return .rejected(.notResizable) }
        if frame.width < policy.minimumSize || frame.height < policy.minimumSize { return .rejected(.tooSmall) }
        return .candidate(frame)
    }

    private static func isReal(_ rect: TileRect) -> Bool {
        rect.x.isFinite && rect.y.isFinite && rect.width.isFinite && rect.height.isFinite
    }
}
