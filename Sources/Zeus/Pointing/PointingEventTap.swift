import AppKit
import CoreGraphics
import Foundation
import ZeusCore

/// Keyboard stream for the pointing hold: a listen-only session CGEvent tap, with an NSEvent
/// global monitor as a fallback when the tap cannot be created.
///
/// Isolation: the tap callback and the monitor handlers are system callbacks. They are written
/// here, in nonisolated code, never inside a `@MainActor` type, so they carry no main-actor
/// executor assumption (the crash class in `SystemAuthorization` and `OffMainAudioCallbacks`).
/// The only thing they do is copy plain values and hand them to `sink` on the main actor.
///
/// Permission: `CGEvent.tapCreate` with `.listenOnly` needs Input Monitoring. This type never
/// prompts; it returns false and the caller shows a notice.
final class PointingEventTap: @unchecked Sendable {
    typealias Sink = @MainActor @Sendable (ShortcutEvent, TimeInterval) -> Void

    private let lock = NSLock()
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var monitors: [Any] = []
    private let sink: Sink

    init(sink: @escaping Sink) { self.sink = sink }
    deinit { stop() }

    /// Idempotent. Returns true when either the tap or the fallback monitor is running.
    nonisolated func start() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let port {
            CGEvent.tapEnable(tap: port, enable: true)
            return true
        }
        if !monitors.isEmpty { return true }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        if let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                           eventsOfInterest: mask, callback: pointingTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()),
           let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) {
            port = created; source = runLoopSource
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: created, enable: true)
            return true
        }
        return installFallbackLocked()
    }

    nonisolated func stop() {
        lock.lock(); defer { lock.unlock() }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        port = nil; source = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
    }

    var usesEventTap: Bool { lock.withLock { port != nil } }

    nonisolated fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system turns a slow or interrupted tap off. Turn it back on.
            lock.lock(); let current = port; lock.unlock()
            if let current { CGEvent.tapEnable(tap: current, enable: true) }
        case .flagsChanged, .keyDown, .keyUp:
            let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            var mods: ShortcutModifiers = []
            if flags.contains(.maskControl) { mods.insert(.control) }
            if flags.contains(.maskAlternate) { mods.insert(.option) }
            if flags.contains(.maskShift) { mods.insert(.shift) }
            if flags.contains(.maskCommand) { mods.insert(.command) }
            if flags.contains(.maskSecondaryFn) { mods.insert(.function) }
            let converted: ShortcutEvent?
            switch type {
            case .flagsChanged: converted = .flags(keyCode: code, modifiers: mods)
            case .keyDown:
                converted = event.getIntegerValueField(.keyboardEventAutorepeat) != 0 ? nil
                    : .keyDown(keyCode: code, modifiers: mods)
            default: converted = .keyUp(keyCode: code)
            }
            if let converted { deliver(converted) }
        default: break
        }
    }

    private nonisolated func deliver(_ event: ShortcutEvent) {
        let time = ProcessInfo.processInfo.systemUptime
        let sink = self.sink
        if Thread.isMainThread {
            MainActor.assumeIsolated { sink(event, time) }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { sink(event, time) } }
        }
    }

    private nonisolated func installFallbackLocked() -> Bool {
        // NSEvent global monitors deliver on the main thread and need Accessibility or Input Monitoring.
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [self] event in
            if let converted = Self.convert(event) { deliver(converted) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [self] event in
            if let converted = Self.convert(event) { deliver(converted) }
            return event
        }
        monitors = [global, local].compactMap { $0 }
        return !monitors.isEmpty
    }

    private nonisolated static func convert(_ event: NSEvent) -> ShortcutEvent? {
        let mods = ShortcutModifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        switch event.type {
        case .flagsChanged: return .flags(keyCode: event.keyCode, modifiers: mods)
        case .keyDown: return event.isARepeat ? nil : .keyDown(keyCode: event.keyCode, modifiers: mods)
        case .keyUp: return .keyUp(keyCode: event.keyCode)
        default: return nil
        }
    }
}

/// A C callback cannot capture. It forwards to the owner through `userInfo` and always passes the
/// event through unchanged (the tap is listen-only and cannot swallow keys).
private func pointingTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon {
        Unmanaged<PointingEventTap>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
