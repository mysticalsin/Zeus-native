import AppKit
import ObjectiveC
import ZeusCore

/// N1-N3: one place that maps policy to `NSWindow.sharingType` for every Zeus surface.
@MainActor
enum ZeusWindowSharing {
    enum Surface {
        case zeusStandard
        case prompterOwnHide(Bool)
    }

    static func policy(showInScreenSharing: Bool, meetingActive: Bool, teleprompterSessionHidden: Bool) -> Bool {
        ZeusScreenSharePolicy.zeusSurfacesVisible(
            showInScreenSharing: showInScreenSharing,
            meetingActive: meetingActive,
            teleprompterSessionHidden: teleprompterSessionHidden
        )
    }

    static func sharingType(visibleInShare: Bool, surface: Surface) -> NSWindow.SharingType {
        switch surface {
        case .zeusStandard:
            return visibleInShare ? .readOnly : .none
        case .prompterOwnHide(let hidden):
            return visibleInShare && !hidden ? .readOnly : .none
        }
    }

    static func apply(to window: NSWindow, visibleInShare: Bool, surface: Surface, force: Bool = false) {
        let want = sharingType(visibleInShare: visibleInShare, surface: surface)
        let wantHidden = want == .none
        let getterHidden: Bool? = switch window.sharingType {
        case .none: true
        case .readOnly: false
        default: nil
        }
        // A popup menu contains the pointer while the row is clicked. It is not the window
        // whose capture exclusion gets stuck, and flipping its mouse acceptance would eat the click.
        let pointerOnWindow = window.level.rawValue < NSWindow.Level.popUpMenu.rawValue
            && !window.ignoresMouseEvents
            && window.frame.contains(NSEvent.mouseLocation)
        let update = CaptureExclusionUpdate(
            wantHidden: wantHidden,
            rememberedHidden: rememberedHidden(on: window),
            getterHidden: getterHidden,
            pointerOnWindow: pointerOnWindow,
            force: force)
        guard let steps = update.steps else { return }
        let acceptMouseAgain = pointerOnWindow
        let wasIgnoring = window.ignoresMouseEvents
        if acceptMouseAgain { window.ignoresMouseEvents = true }
        for hidden in steps {
            window.sharingType = hidden ? .none : .readOnly
        }
        if acceptMouseAgain { window.ignoresMouseEvents = wasIgnoring }
        remember(wantHidden, on: window)
    }

    static func refresh(
        showInScreenSharing: Bool,
        meetingActive: Bool,
        teleprompterSessionHidden: Bool,
        extraWindows: [NSWindow] = [],
        force: Bool = false
    ) {
        let visible = policy(
            showInScreenSharing: showInScreenSharing,
            meetingActive: meetingActive,
            teleprompterSessionHidden: teleprompterSessionHidden
        )
        for window in NSApp.windows + extraWindows {
            if let prompter = window as? PrompterPanel {
                apply(to: window, visibleInShare: visible, surface: .prompterOwnHide(prompter.hiddenFromCapture), force: force)
            } else {
                apply(to: window, visibleInShare: visible, surface: .zeusStandard, force: force)
            }
        }
        NotchControllerBridge.controller?.applyScreenSharePolicy(visibleInShare: visible)
        BuddyControllerBridge.shared?.applyScreenSharePolicy(visibleInShare: visible)
        MarkOverlay.shared.applyScreenSharePolicy(visibleInShare: visible)
        ScreenEdgeGlowController.shared.applyScreenSharePolicy(visibleInShare: visible)
        EdgeWaveController.shared.applyScreenSharePolicy(visibleInShare: visible)
        ScreenCornerOverlay.shared.applyScreenSharePolicy(visibleInShare: visible)
        TilingFocusBorder.shared.applyScreenSharePolicy(visibleInShare: visible)
        TilingKeySheet.shared.applyScreenSharePolicy(visibleInShare: visible)
        PolyglotCaptionBridge.shared?.applyScreenSharePolicy(visibleInShare: visible)
    }

    static func refreshFromAppState(teleprompterSessionHidden: Bool = false, force: Bool = false) {
        let store = SettingsStore.shared
        let show = store.bool(ZeusScreenSharePolicy.showInSharingKey)
        refresh(
            showInScreenSharing: show,
            meetingActive: MeetingState.active,
            teleprompterSessionHidden: teleprompterSessionHidden,
            force: force
        )
    }

    private static func rememberedHidden(on window: NSWindow) -> Bool? {
        (objc_getAssociatedObject(window, &SharingMemory.key) as? SharingWriteRecord)?.hidden
    }

    private static func remember(_ hidden: Bool, on window: NSWindow) {
        objc_setAssociatedObject(window, &SharingMemory.key, SharingWriteRecord(hidden: hidden), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

private enum SharingMemory {
    nonisolated(unsafe) static var key: UInt8 = 0
}

private final class SharingWriteRecord: NSObject {
    let hidden: Bool
    init(hidden: Bool) { self.hidden = hidden }
}

/// The quick "Show Zeus in screen shares" / "Hide Zeus from screen shares" row used by the top bar's
/// "..." menu and the menu bar menu. It writes the same setting as Settings (General and Appearance),
/// whose change handler re-applies the policy to every Zeus window at once, no restart.
@MainActor
enum ScreenShareQuickToggle {
    static var isShown: Bool { SettingsStore.shared.bool(ZeusScreenSharePolicy.showInSharingKey) }

    /// The row names the action; the checkmark says Zeus is visible to people you share with right now.
    static func menuItem(target: AnyObject, action: Selector) -> NSMenuItem {
        let shown = isShown
        let item = NSMenuItem(title: ScreenShareQuickToggleLogic.title(shown: shown), action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = ScreenShareQuickToggleLogic.rowMarker
        item.isEnabled = true
        item.image = NSImage(systemSymbolName: shown ? "eye.slash" : "eye", accessibilityDescription: nil)
        item.state = shown ? .on : .off
        return item
    }

    /// The menu must tell the catcher when it opens. The catcher is retained here;
    /// `NSMenu.delegate` does not keep it.
    static func installCatcher(on menu: NSMenu) {
        ScreenShareMenuCatcher.shared.install(on: menu)
    }

    static func toggle() {
        ScreenShareMenuCatcher.shared.markToggled()
        let shown = ScreenShareQuickToggleLogic.nextShown(isShown)
        SettingsStore.shared.set(ZeusScreenSharePolicy.showInSharingKey, ScreenShareQuickToggleLogic.storedValue(shown: shown))
    }

    static func allowMenuAction() -> Bool { ScreenShareMenuCatcher.shared.allowAction() }
}

/// Hears a mouse-up on the screen-share row even when menu tracking ignores it.
///
/// Tracking will not perform a row the pointer was already inside, so a click that
/// does not move — the pointer left on the row — never reaches the item action.
/// The item action can also arrive for that same mouse-up. The mouse-up flips,
/// and the action is ignored until the menu opens again.
@MainActor
final class ScreenShareMenuCatcher: NSObject, NSMenuDelegate {
    static let shared = ScreenShareMenuCatcher()
    private var monitor: Any?
    private var ledger = ScreenShareClickLedger()
    private var toggled = false
    private weak var openMenu: NSMenu?

    func install(on menu: NSMenu) { menu.delegate = self }
    func markToggled() { toggled = true }
    func allowAction() -> Bool { ledger.action() }

    func menuWillOpen(_ menu: NSMenu) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        toggled = false
        ledger.menuClosed()
        openMenu = menu
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            let eat = MainActor.assumeIsolated { self?.handleMouseUp(event) ?? false }
            return eat ? nil : event
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        openMenu = nil
        let token = monitor
        monitor = nil
        if let token { NSEvent.removeMonitor(token) }
        let needsForce = toggled
        toggled = false
        guard needsForce else { return }
        // The write from the click ran inside tracking, which can drop it while the
        // pointer is still on the row. Write again now, and once more after tracking returns.
        ZeusWindowSharing.refreshFromAppState(force: true)
        DispatchQueue.main.async { ZeusWindowSharing.refreshFromAppState(force: true) }
    }

    private func handleMouseUp(_ event: NSEvent) -> Bool {
        guard openMenu != nil, Self.pointerIsOnRow(event) else { return false }
        ledger.pointerUpOnRow()
        ScreenShareQuickToggle.toggle()
        let menu = openMenu
        DispatchQueue.main.async { menu?.cancelTracking() }
        return true
    }

    private static func pointerIsOnRow(_ event: NSEvent) -> Bool {
        let mouse = NSEvent.mouseLocation
        var windows: [NSWindow] = []
        if let window = event.window { windows.append(window) }
        for window in NSApp.windows where window.frame.contains(mouse) {
            if !windows.contains(where: { $0 === window }) { windows.append(window) }
        }
        for window in windows {
            guard let content = window.contentView else { continue }
            let inWindow = window.convertPoint(fromScreen: mouse)
            let inContent = content.convert(inWindow, from: nil)
            if let item = menuItem(at: inContent, in: content),
               ScreenShareQuickToggleLogic.isToggleRow(item.representedObject as? String) {
                return true
            }
        }
        return false
    }

    /// The item that owns the deepest view under `point`, which is in `view`'s space.
    /// A view that contains the point but is not a menu row does not claim the click.
    private static func menuItem(at point: NSPoint, in view: NSView) -> NSMenuItem? {
        for subview in view.subviews.reversed() {
            let local = subview.convert(point, from: view)
            guard subview.bounds.contains(local) else { continue }
            return menuItem(at: local, in: subview) ?? subview.enclosingMenuItem
        }
        return view.enclosingMenuItem
    }
}

@MainActor
enum BuddyControllerBridge {
    static weak var shared: BuddyController?
}

@MainActor
enum PolyglotCaptionBridge {
    static weak var shared: PolyglotCaptionSharing?
}

@MainActor
protocol PolyglotCaptionSharing: AnyObject {
    func applyScreenSharePolicy(visibleInShare: Bool)
}
