import Foundation
import IOKit

/// Whether the lid is closed, from `AppleClamshellState` on IOPMrootDomain. Runs only while a
/// lid-closed session is armed. IOPMrootDomain's general-interest notification wakes it on a
/// clamshell change, and a 2 s timer reads the same key as a backstop. A change is delivered once
/// two reads agree, so a lid that bounces is not acted on.
@MainActor
final class LidMonitor {
    static let interval: TimeInterval = 2

    /// True when the lid is closed. Called on the main thread.
    var onChange: (Bool) -> Void = { _ in }
    private(set) var isClosed: Bool?

    private let read: () -> Bool?
    private var pending: Bool?
    private var timer: Timer?
    private var port: IONotificationPortRef?
    private var service: io_service_t = 0
    private var notification: io_object_t = 0

    init(read: @escaping () -> Bool? = LidMonitor.readClamshell) {
        self.read = read
    }

    var isRunning: Bool { timer != nil }

    /// True closed, false open, nil on a Mac with no lid.
    nonisolated static func readClamshell() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }
        return (value as? Bool) ?? (value as? NSNumber)?.boolValue
    }

    func start() {
        guard timer == nil else { return }
        isClosed = read()
        pending = nil
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        listen()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pending = nil
        if notification != 0 { IOObjectRelease(notification); notification = 0 }
        if let port {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)
            IONotificationPortDestroy(port)
            self.port = nil
        }
        if service != 0 { IOObjectRelease(service); service = 0 }
    }

    /// One read. A new state becomes pending; the next read that agrees delivers it.
    func check() {
        guard let now = read() else { return }
        if now == isClosed { pending = nil; return }
        if pending == now {
            pending = nil
            isClosed = now
            onChange(now)
        } else {
            pending = now
        }
    }

    private func listen() {
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0, let made = IONotificationPortCreate(kIOMainPortDefault) else { return }
        port = made
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(made).takeUnretainedValue(), .commonModes)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddInterestNotification(made, service, kIOGeneralInterest, { context, _, _, _ in
            guard let context else { return }
            // The source is on the main run loop, so this runs on the main thread.
            MainActor.assumeIsolated {
                let monitor = Unmanaged<LidMonitor>.fromOpaque(context).takeUnretainedValue()
                monitor.check()
                // Confirm quickly instead of waiting a whole tick.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak monitor] in
                    MainActor.assumeIsolated { monitor?.check() }
                }
            }
        }, context, &notification)
        if result != KERN_SUCCESS { notification = 0 }
    }
}
