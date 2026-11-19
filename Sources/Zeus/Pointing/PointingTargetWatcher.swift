import ApplicationServices
import AppKit
import ZeusCore

/// Carries an AXObserver notification name from the C callback to the main actor.
final class PointingAXBox: @unchecked Sendable {
    let sink: @MainActor @Sendable (String) -> Void
    init(sink: @escaping @MainActor @Sendable (String) -> Void) { self.sink = sink }
}

/// The C callback cannot capture. It reads the box from `refcon` and hops to the main actor
/// explicitly; it touches no AX state itself.
private func pointingObserverCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                                      _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let box = Unmanaged<PointingAXBox>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    let sink = box.sink
    DispatchQueue.main.async { MainActor.assumeIsolated { sink(name) } }
}

/// Nonisolated factory: the observer's callback is created here, never inside a `@MainActor` type.
enum PointingAXObserver {
    nonisolated static func make(pid: pid_t) -> AXObserver? {
        var created: AXObserver?
        guard AXObserverCreate(pid, pointingObserverCallback, &created) == .success else { return nil }
        return created
    }
}

/// Watches the Accessibility element a mark points at, so a mark never stays on a control that has
/// moved, resized, changed or gone. All AX calls run on the main actor, each bounded by a 0.1 s
/// messaging timeout. It needs Accessibility trust the owner already granted and never asks for it.
@MainActor
final class PointingTargetWatcher {
    typealias Handler = @MainActor @Sendable (PointingStaleTarget.Event) -> Void

    private var observer: AXObserver?
    private var source: CFRunLoopSource?
    private var box: PointingAXBox?
    private var element: AXUIElement?
    private var registered: [AXUIElement] = []
    private(set) var isWatching = false

    /// Starts watching the element under `point` (Quartz global points). Returns its frame, or nil when
    /// Accessibility is not trusted or nothing usable is there.
    func start(atQuartzPoint point: CGPoint, handler: @escaping Handler) -> CGRect? {
        stop()
        guard AXIsProcessTrusted(), point.x.isFinite, point.y.isFinite else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, PointingTargetProbe.messagingTimeout)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &found) == .success,
              let target = found else { return nil }
        AXUIElementSetMessagingTimeout(target, PointingTargetProbe.messagingTimeout)
        guard let frame = PointingTargetProbe.frame(of: target), frame.width > 0, frame.height > 0 else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(target, &pid) == .success, pid != getpid(),
              let created = PointingAXObserver.make(pid: pid) else { return nil }

        let carrier = PointingAXBox { name in
            if let event = PointingStaleTarget.Event(axNotification: name) { handler(event) }
        }
        let refcon = Unmanaged.passUnretained(carrier).toOpaque()
        var targets = [target]
        if let window = windowOf(target) { targets.append(window) }
        for item in targets {
            for name in PointingStaleTarget.Event.observedNotifications {
                // An element that does not support a notification just refuses it.
                if AXObserverAddNotification(created, item, name as CFString, refcon) == .success { registered.append(item) }
            }
        }
        guard !registered.isEmpty else { return nil }
        let runLoopSource = AXObserverGetRunLoopSource(created)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        observer = created; source = runLoopSource; box = carrier; element = target
        isWatching = true
        return frame
    }

    /// A fresh read of the watched element's frame (Quartz points), for the per-beat drift check.
    /// nil when the element can no longer be read.
    func currentFrame() -> CGRect? {
        guard isWatching, let element else { return nil }
        return PointingTargetProbe.frame(of: element)
    }

    func stop() {
        if let observer {
            for item in registered {
                for name in PointingStaleTarget.Event.observedNotifications {
                    _ = AXObserverRemoveNotification(observer, item, name as CFString)
                }
            }
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        observer = nil; source = nil; box = nil; element = nil; registered = []
        isWatching = false
    }

    private func windowOf(_ target: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(target, kAXWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
