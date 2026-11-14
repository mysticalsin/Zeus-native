import AppKit
import ApplicationServices
import ZeusCore

/// The Accessibility window driver for tiling. It lists the standard windows of regular apps on the current
/// Space, writes frames to the windows it listed, and focuses one of them. It never asks for a permission: with Accessibility off every
/// entry point does nothing and `isTrusted` says so. No window title or content is read.
///
/// Frames are in the engine's space (top left of the main display, y down), which is what Accessibility and the
/// window list already use. AppKit coordinates appear only in `displays()`, converted once through `TileDisplay`.
/// Every decision that can be pure (admission, read-back tolerance, matching windows to slots) is in ZeusCore.
@MainActor
final class AXTilingWindowDriver: TilingWindowDriver {
    /// Seconds one listing pass may spend, checked before every app and every window. An app the pass could not
    /// finish is left out of the listing and named in `unreadPIDs`.
    static let passBudget = 0.5
    /// A hung app answers each call only after this timeout.
    static let messagingTimeout: Float = 0.25

    private let trustCheck: @MainActor () -> Bool
    /// The admission policy of the last listing, so a window can be judged again before it is given the keyboard.
    private var lastPolicy: TileAdmissionPolicy?
    private var allocator = TileIDAllocator()
    /// The live element behind each id handed out, by app. Identity is `CFEqual` on the element.
    private var known: [pid_t: [(element: AXUIElement, id: TileWindowID)]] = [:]
    /// The windows the last listing returned. Only these are ever written or focused: `known` also holds
    /// minimized, full-screen and other-Space windows, which admission rejects.
    private var admitted: Set<TileWindowID> = []
    /// The apps the last listing could not read in time: an app that did not answer, or was not reached before the
    /// pass budget ran out. Every running app while Accessibility is off.
    private(set) var unreadPIDs: Set<Int32> = []

    init(isTrusted: @escaping @MainActor () -> Bool = { AccessibilityGate.trusted }) {
        trustCheck = isTrusted
    }

    var isTrusted: Bool { trustCheck() }

    // MARK: Displays

    func displays() -> [TileDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            let appKit = Self.tileRect(screen.frame)
            let bounds = CGDisplayBounds(number)
            let engine = bounds.width > 0 && bounds.height > 0
                ? Self.tileRect(bounds)
                : TileDisplay.engineFrame(appKitFrame: appKit, mainScreenHeight: Double(NSScreen.screens.first?.frame.height ?? screen.frame.height))
            return TileDisplay(id: number, appKitFrame: appKit, appKitVisibleFrame: Self.tileRect(screen.visibleFrame), engineFrame: engine)
        }
    }

    // MARK: Windows

    func windows(config: TileConfig) -> [TileWindowRef] {
        guard isTrusted else {
            // Nothing from before the permission was revoked may survive its return.
            known = [:]
            admitted = []
            lastPolicy = nil
            unreadPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
            return []
        }
        let policy = TileAdmissionPolicy(config: config, zeusPID: ProcessInfo.processInfo.processIdentifier,
                                         zeusBundleID: Bundle.main.bundleIdentifier)
        lastPolicy = policy
        let onScreen = Self.onScreenWindows()
        let deadline = ProcessInfo.processInfo.systemUptime + Self.passBudget
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let alive = Set(running.map(\.processIdentifier))
        known = known.filter { alive.contains($0.key) }

        var out: [TileWindowRef] = []
        var unread = Set<pid_t>()
        for app in running {
            let pid = app.processIdentifier
            if TileAdmission.appRejection(pid: pid, bundleID: app.bundleIdentifier,
                                          isRegularApp: app.activationPolicy == .regular, policy: policy) != nil {
                known[pid] = nil
                continue
            }
            // A hidden app has no window on screen, so every window would be rejected as on another Space. Its
            // elements stay known so its ids are the same when it is shown again.
            if app.isHidden { continue }
            guard let refs = scan(app, onScreen: onScreen, policy: policy, deadline: deadline) else {
                unread.insert(pid)
                continue
            }
            out += refs
        }
        admitted = Set(out.map(\.id))
        unreadPIDs = unread
        return out
    }

    /// The admitted windows of one app (none when it says it has none), or nil when the app did not answer in time,
    /// on its list or on any one window. Nothing is guessed: the caller leaves an unanswered app out of the listing and
    /// names it unread, so a window that is only slow never looks closed.
    private func scan(_ app: NSRunningApplication, onScreen: [TileOnScreenWindow], policy: TileAdmissionPolicy,
                      deadline: TimeInterval) -> [TileWindowRef]? {
        guard ProcessInfo.processInfo.systemUptime <= deadline else { return nil }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, Self.messagingTimeout)
        var raw: CFTypeRef?
        let list: [AXUIElement]
        switch TileWindowsAnswer.classify(axError: AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &raw).rawValue) {
        case .answered:
            guard let windows = raw as? [AXUIElement] else { return nil }
            list = windows
        case .noWindows:
            // A definite "none" (an app that closed its last window): the app was read, so no slot of it is kept.
            list = []
        case .unread:
            return nil
        }

        var facts: [TileWindowFacts] = []
        for window in list {
            guard ProcessInfo.processInfo.systemUptime <= deadline else { return nil }
            AXUIElementSetMessagingTimeout(window, Self.messagingTimeout)
            guard let read = Self.facts(of: window, app: app) else { return nil }
            facts.append(read)
        }
        // The windows of one app are judged together, so two windows at one frame cannot both borrow one on-screen entry.
        let verdicts = TileAdmission.rejections(facts, onScreen: onScreen, policy: policy)
        var refs: [TileWindowRef] = []
        for (index, window) in list.enumerated() where verdicts[index] == nil {
            guard let frame = facts[index].frame, let bundleID = facts[index].bundleID else { continue }
            refs.append(TileWindowRef(id: identity(of: window, pid: pid), bundleID: bundleID, frame: frame))
        }
        // A window that left the app's list is gone: its element and number are dropped.
        known[pid] = known[pid]?.filter { entry in list.contains { CFEqual($0, entry.element) } }
        return refs
    }

    private func identity(of window: AXUIElement, pid: pid_t) -> TileWindowID {
        if let match = known[pid]?.first(where: { CFEqual($0.element, window) }) { return match.id }
        let id = allocator.next(pid: pid)
        known[pid, default: []].append((window, id))
        return id
    }

    /// The element of a window the last listing returned. Any other id has no element here.
    private func element(for window: TileWindowID) -> AXUIElement? {
        guard admitted.contains(window) else { return nil }
        return known[window.pid]?.first { $0.id == window }?.element
    }

    // MARK: Reading

    private static let windowAttributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXMinimizedAttribute, "AXFullScreen",
                                           kAXPositionAttribute, kAXSizeAttribute]

    /// Everything admission needs, from one round trip plus the settable check. A property that does not read is nil.
    /// A window with no full-screen attribute cannot be in full screen, so that one reads as false. The result is nil
    /// when the round trip itself did not complete (`TileWindowsAnswer.windowRead`): then nothing is known about the window.
    private static func facts(of window: AXUIElement, app: NSRunningApplication) -> TileWindowFacts? {
        var facts = TileWindowFacts(pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                                    isRegularApp: app.activationPolicy == .regular, role: nil, subrole: nil,
                                    isMinimized: nil, isFullScreen: nil, isSizeSettable: nil, frame: nil)
        var raw: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(window, windowAttributes as CFArray, [], &raw)
        guard TileWindowsAnswer.windowRead(axError: error.rawValue) else { return nil }
        guard let values = raw as? [AnyObject], values.count == windowAttributes.count else { return facts }

        func flag(_ index: Int) -> Bool? {
            let value = values[index]
            guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
            return CFBooleanGetValue(value as! CFBoolean) // swiftlint:disable:this force_cast
        }
        func unsupported(_ index: Int) -> Bool {
            let value = values[index]
            guard CFGetTypeID(value) == AXValueGetTypeID() else { return false }
            let axValue = value as! AXValue // swiftlint:disable:this force_cast
            var error = AXError.success
            return AXValueGetType(axValue) == .axError && AXValueGetValue(axValue, .axError, &error) && error == .attributeUnsupported
        }

        facts.role = values[0] as? String
        facts.subrole = values[1] as? String
        facts.isMinimized = flag(2)
        facts.isFullScreen = flag(3) ?? (unsupported(3) ? false : nil)
        facts.frame = frame(position: values[4], size: values[5])
        // The settable check is one more call, so it runs only for a window that could still be admitted.
        let standard = facts.role == "AXWindow" && facts.subrole == "AXStandardWindow"
        facts.isSizeSettable = standard ? AXFinder.isSettable(window, kAXSizeAttribute) : false
        return facts
    }

    /// A frame from the position and size values of one read, or nil when either is not the expected value type.
    private static func frame(position: AnyObject, size: AnyObject) -> TileRect? {
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), // swiftlint:disable:this force_cast
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil } // swiftlint:disable:this force_cast
        return tileRect(CGRect(origin: point, size: extent))
    }

    /// The system's on-screen windows: owner, bounds and level only. No title is read and no capture permission is needed.
    private static func onScreenWindows() -> [TileOnScreenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return TileOnScreenWindow(pid: pid, frame: tileRect(rect), layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                                      ownerName: info[kCGWindowOwnerName as String] as? String)
        }
    }

    // MARK: Writing

    /// Size, then position, then size again (an app that clamps while crossing displays settles on the last
    /// write), then reads the frame back. True only when it landed within the tolerance. One attempt, no retry.
    func setFrame(_ frame: TileRect, for window: TileWindowID) -> Bool {
        guard isTrusted, let element = element(for: window), !frame.isEmpty,
              frame.x.isFinite, frame.y.isFinite else { return false }
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        var size = CGSize(width: frame.width, height: frame.height)
        var origin = CGPoint(x: frame.x, y: frame.y)
        Self.write(&size, .cgSize, kAXSizeAttribute, on: element)
        Self.write(&origin, .cgPoint, kAXPositionAttribute, on: element)
        Self.write(&size, .cgSize, kAXSizeAttribute, on: element)
        return TileReadBack.landed(intended: frame, actual: Self.readFrame(of: element))
    }

    private static func write<T>(_ value: inout T, _ type: AXValueType, _ attribute: String, on element: AXUIElement) {
        guard let axValue = AXValueCreate(type, &value) else { return }
        AXUIElementSetAttributeValue(element, attribute as CFString, axValue)
    }

    /// The window's frame in engine coordinates. Accessibility already reports it with the origin at the top left of
    /// the main display, so it is read as is, with no AppKit conversion to undo.
    private static func readFrame(of element: AXUIElement) -> TileRect? {
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, [kAXPositionAttribute, kAXSizeAttribute] as CFArray, [], &raw) == .success,
              let values = raw as? [AnyObject], values.count == 2 else { return nil }
        return frame(position: values[0], size: values[1])
    }

    /// Gives `window` the keyboard only when it is still a window tiling would list: the listing it came from can be
    /// minutes old, and raising a window that has since been minimized or sent to another Space would bring it back or
    /// switch Spaces. The app is read again, in one pass with the listing's budget, and a window that does not pass
    /// admission now, or an app that does not answer, is left alone.
    func focus(_ window: TileWindowID) {
        guard isTrusted, let element = element(for: window), stillAdmitted(window) else { return }
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    private func stillAdmitted(_ window: TileWindowID) -> Bool {
        guard let policy = lastPolicy, let app = NSRunningApplication(processIdentifier: window.pid),
              !app.isTerminated, !app.isHidden else { return false }
        let deadline = ProcessInfo.processInfo.systemUptime + Self.passBudget
        guard let refs = scan(app, onScreen: Self.onScreenWindows(), policy: policy, deadline: deadline) else { return false }
        return refs.contains { $0.id == window }
    }

    /// The front app's focused window, when the last listing admitted it, and whether that window is in full screen.
    /// Zeus itself is never read: admission refuses its windows, and a read into this process from the main thread
    /// can stall its own interface. One app, two reads, with the same messaging timeout as everything else; anything unreadable is "not full
    /// screen" and "no focused window", which leaves the layout as it is.
    func frontmost() -> TileFrontmost {
        guard isTrusted, let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return .none }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, Self.messagingTimeout)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return .none }
        let window = raw as! AXUIElement // swiftlint:disable:this force_cast
        AXUIElementSetMessagingTimeout(window, Self.messagingTimeout)
        var full: CFTypeRef?
        var isFullScreen = false
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &full) == .success, let full,
           CFGetTypeID(full) == CFBooleanGetTypeID() {
            isFullScreen = CFBooleanGetValue(full as! CFBoolean) // swiftlint:disable:this force_cast
        }
        let entry = known[pid]?.first { CFEqual($0.element, window) }
        let focused = entry.flatMap { admitted.contains($0.id) ? $0.id : nil }
        return TileFrontmost(focused: focused, isFullScreen: isFullScreen)
    }

    private static func tileRect(_ rect: CGRect) -> TileRect {
        TileRect(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }
}
