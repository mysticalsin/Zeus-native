import AppKit
import ApplicationServices
import ZeusCore

/// The Accessibility window driver for tiling. It lists the standard windows of regular apps on the current
/// Space, writes frames, and focuses a window. It never asks for a permission: with Accessibility off every
/// entry point does nothing and `isTrusted` says so. No window title or content is read.
///
/// Frames are in the engine's space (top left of the main display, y down), which is what Accessibility and the
/// window list already use. AppKit coordinates appear only in `displays()`, converted once through `TileDisplay`.
/// Every decision that can be pure (admission, read-back tolerance, matching windows to slots) is in ZeusCore.
@MainActor
final class AXTilingWindowDriver: TilingWindowDriver {
    /// Seconds one listing pass may spend. Apps it has not reached keep their last answer, so a slow pass never
    /// makes the layout think their windows are gone.
    static let passBudget = 0.5
    /// A hung app answers each call only after this timeout.
    static let messagingTimeout: Float = 0.25

    private let trustCheck: @MainActor () -> Bool
    private var allocator = TileIDAllocator()
    /// The live element behind each id handed out, by app. Identity is `CFEqual` on the element.
    private var known: [pid_t: [(element: AXUIElement, id: TileWindowID)]] = [:]
    /// The last admitted windows of each app, used when a pass runs out of time or an app does not answer.
    private var lastListing: [pid_t: [TileWindowRef]] = [:]
    /// False when the last listing reused an app's earlier answer.
    private(set) var lastPassComplete = true

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
        guard isTrusted else { return [] }
        let policy = TileAdmissionPolicy(config: config, zeusPID: ProcessInfo.processInfo.processIdentifier,
                                         zeusBundleID: Bundle.main.bundleIdentifier)
        let onScreen = Self.onScreenWindows()
        let deadline = ProcessInfo.processInfo.systemUptime + Self.passBudget
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let alive = Set(running.map(\.processIdentifier))
        known = known.filter { alive.contains($0.key) }
        lastListing = lastListing.filter { alive.contains($0.key) }

        var out: [TileWindowRef] = []
        var complete = true
        for app in running {
            let pid = app.processIdentifier
            if TileAdmission.appRejection(pid: pid, bundleID: app.bundleIdentifier,
                                          isRegularApp: app.activationPolicy == .regular, policy: policy) != nil {
                lastListing[pid] = nil
                known[pid] = nil
                continue
            }
            if ProcessInfo.processInfo.systemUptime > deadline {
                complete = false
                out += lastListing[pid] ?? []
                continue
            }
            if let refs = scan(app, onScreen: onScreen, policy: policy) {
                lastListing[pid] = refs
                out += refs
            } else {
                complete = false
                out += lastListing[pid] ?? []
            }
        }
        lastPassComplete = complete
        return out
    }

    /// The admitted windows of one app, or nil when the app did not answer.
    private func scan(_ app: NSRunningApplication, onScreen: [TileOnScreenWindow], policy: TileAdmissionPolicy) -> [TileWindowRef]? {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, Self.messagingTimeout)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &raw) == .success,
              let list = raw as? [AXUIElement] else { return nil }

        var refs: [TileWindowRef] = []
        for window in list {
            AXUIElementSetMessagingTimeout(window, Self.messagingTimeout)
            let facts = Self.facts(of: window, app: app)
            guard TileAdmission.rejection(facts, onScreen: onScreen, policy: policy) == nil,
                  let frame = facts.frame, let bundleID = facts.bundleID else { continue }
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

    private func element(for window: TileWindowID) -> AXUIElement? {
        known[window.pid]?.first { $0.id == window }?.element
    }

    // MARK: Reading

    private static let windowAttributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXMinimizedAttribute, "AXFullScreen",
                                           kAXPositionAttribute, kAXSizeAttribute]

    /// Everything admission needs, from one round trip plus the settable check. A property that does not read is nil.
    /// A window with no full-screen attribute cannot be in full screen, so that one reads as false.
    private static func facts(of window: AXUIElement, app: NSRunningApplication) -> TileWindowFacts {
        var facts = TileWindowFacts(pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                                    isRegularApp: app.activationPolicy == .regular, role: nil, subrole: nil,
                                    isMinimized: nil, isFullScreen: nil, isSizeSettable: nil, frame: nil)
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(window, windowAttributes as CFArray, [], &raw) == .success,
              let values = raw as? [AnyObject], values.count == windowAttributes.count else { return facts }

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
        var point = CGPoint.zero
        var size = CGSize.zero
        if CFGetTypeID(values[4]) == AXValueGetTypeID(), CFGetTypeID(values[5]) == AXValueGetTypeID(),
           AXValueGetValue(values[4] as! AXValue, .cgPoint, &point), AXValueGetValue(values[5] as! AXValue, .cgSize, &size) { // swiftlint:disable:this force_cast
            facts.frame = tileRect(CGRect(origin: point, size: size))
        }
        // The settable check is one more call, so it runs only for a window that could still be admitted.
        let standard = facts.role == "AXWindow" && facts.subrole == "AXStandardWindow"
        facts.isSizeSettable = standard ? AXFinder.isSettable(window, kAXSizeAttribute) : false
        return facts
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

    /// The window's frame in engine coordinates, through the shared Accessibility helpers.
    private static func readFrame(of element: AXUIElement) -> TileRect? {
        AXFinder.frame(of: element).map { tileRect(AXSnapshotter.quartzRect($0)) }
    }

    func focus(_ window: TileWindowID) {
        guard isTrusted, let element = element(for: window) else { return }
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    private static func tileRect(_ rect: CGRect) -> TileRect {
        TileRect(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }
}
