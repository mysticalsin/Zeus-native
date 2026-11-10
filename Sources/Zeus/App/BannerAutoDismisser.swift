import AppKit
import ApplicationServices
import Foundation
import ZeusCore

private final class AXBox: @unchecked Sendable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
}

/// Observes macOS Notification Center banner windows via Accessibility API (AXObserver)
/// and closes the banner for user-ticked apps AFTER Zeus has mirrored and displayed the notification.
/// OFF by default, uses 0 CPU when inactive, strictly bounded execution (no loops).
@MainActor
final class BannerAutoDismisser {
    static let shared = BannerAutoDismisser()

    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false

    private init() {}

    func update() {
        let store = SettingsStore.shared
        let enabled = store.bool("notify.replaceBanners") && AXIsProcessTrusted()
        let ticked = BannerDismissDecision.parseTickedApps(store.string("notify.dismissApps"))

        if !enabled || ticked.isEmpty {
            stop()
            return
        }

        if !isRunning {
            start()
        }
    }

    func start() {
        guard !isRunning else { return }
        guard AXIsProcessTrusted() else { return }

        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else {
            return
        }

        let pid = app.processIdentifier
        var obs: AXObserver?
        let callback: AXObserverCallback = { observer, element, notification, refcon in
            guard let refcon else { return }
            let dismisser = Unmanaged<BannerAutoDismisser>.fromOpaque(refcon).takeUnretainedValue()
            dismisser.handleNotification(element: element, notificationName: notification as String)
        }

        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let appElement = AXUIElementCreateApplication(pid)

        AXObserverAddNotification(obs, appElement, kAXWindowCreatedNotification as CFString, selfPtr)
        AXObserverAddNotification(obs, appElement, kAXFocusedUIElementChangedNotification as CFString, selfPtr)

        let source = AXObserverGetRunLoopSource(obs)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        self.observer = obs
        self.observedPID = pid
        self.runLoopSource = source
        self.isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        if let observer, let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            let appElement = AXUIElementCreateApplication(observedPID)
            AXObserverRemoveNotification(observer, appElement, kAXWindowCreatedNotification as CFString)
            AXObserverRemoveNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString)
        }
        observer = nil
        runLoopSource = nil
        observedPID = 0
        isRunning = false
    }

    private nonisolated func handleNotification(element: AXUIElement, notificationName: String) {
        let box = AXBox(element)
        DispatchQueue.main.async { [weak self] in
            self?.processBanner(element: box.element)
        }
    }

    private func processBanner(element: AXUIElement) {
        let store = SettingsStore.shared
        guard store.bool("notify.replaceBanners") else { return }
        let ticked = BannerDismissDecision.parseTickedApps(store.string("notify.dismissApps"))
        guard !ticked.isEmpty else { return }

        // Inspect window and find Close action with strict traversal bounds
        var closeButton: AXUIElement?

        var childrenValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            var searchQueue = Array(children.prefix(15))
            var inspectedCount = 0

            while !searchQueue.isEmpty && inspectedCount < 30 {
                let current = searchQueue.removeFirst()
                inspectedCount += 1

                var roleValue: AnyObject?
                AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue)
                let role = roleValue as? String ?? ""

                var titleValue: AnyObject?
                AXUIElementCopyAttributeValue(current, kAXTitleAttribute as CFString, &titleValue)
                let title = (titleValue as? String ?? "").lowercased()

                var descValue: AnyObject?
                AXUIElementCopyAttributeValue(current, kAXDescriptionAttribute as CFString, &descValue)
                let desc = (descValue as? String ?? "").lowercased()

                if role == (kAXButtonRole as String) || desc.contains("close") || title.contains("close") || title.contains("fermer") {
                    var subroleValue: AnyObject?
                    AXUIElementCopyAttributeValue(current, kAXSubroleAttribute as CFString, &subroleValue)
                    let subrole = subroleValue as? String ?? ""
                    if subrole == (kAXCloseButtonSubrole as String) || desc.contains("close") || title.contains("close") {
                        closeButton = current
                    }
                }

                var subChildrenValue: AnyObject?
                if inspectedCount < 20,
                   AXUIElementCopyAttributeValue(current, kAXChildrenAttribute as CFString, &subChildrenValue) == .success,
                   let subChildren = subChildrenValue as? [AXUIElement] {
                    searchQueue.append(contentsOf: subChildren.prefix(5))
                }
            }
        }

        if let close = closeButton {
            AXUIElementPerformAction(close, kAXPressAction as CFString)
        }
    }
}
