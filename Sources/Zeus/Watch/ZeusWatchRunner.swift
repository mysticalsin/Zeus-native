import AppKit
import ApplicationServices
import Observation
import UserNotifications
import ZeusCore

@MainActor
@Observable
final class ZeusWatchRunner {
    static let shared = ZeusWatchRunner()

    private(set) var watches: [ZeusWatch] = []
    private var timer: Timer?

    func startWatch(_ watch: ZeusWatch) {
        watches.append(watch)
        armTimer()
    }

    func stopAll() {
        watches.removeAll()
        timer?.invalidate()
        timer = nil
    }

    func stop(label: String) {
        let needle = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle == "watching" || needle == "all" {
            watches.removeAll()
        } else {
            watches.removeAll { $0.label.lowercased().contains(needle) }
        }
        if watches.isEmpty { timer?.invalidate(); timer = nil }
    }

    private func armTimer() {
        timer?.invalidate()
        guard !watches.isEmpty else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    /// A shell watch is trusted only after its test has failed once (the thing was running).
    private var armedShell: Set<UUID> = []
    private var ticking = false
    /// A "finishes" watch that never sees the thing running is dropped after this long.
    private static let armTimeout: TimeInterval = 120

    private func tick() async {
        guard !ticking else { return }
        ticking = true
        defer { ticking = false }
        // The shell tests run off the main thread, with a timeout, before the snapshot is read.
        var shellResults: [String: Bool] = [:]
        for watch in watches {
            guard case .shellTest(let command) = watch.trigger, ZeusWatchVoice.isRunnableTest(command) else { continue }
            let ok = await Self.runTest(command)
            if !ok { armedShell.insert(watch.id) }
            shellResults[command] = ok && armedShell.contains(watch.id)
        }
        let mac = Self.snapshot(shellTests: shellResults)
        var remaining: [ZeusWatch] = []
        for watch in watches {
            let result = ZeusWatchEvaluator.evaluate(watch, mac: mac)
            if result.fired {
                notify(result.message, id: watch.id)
            } else if case .shellTest = watch.trigger, !armedShell.contains(watch.id),
                      Date().timeIntervalSince(watch.created) > Self.armTimeout {
                notify("I never saw \(watch.label) running, so I stopped watching.", id: watch.id)
            } else {
                remaining.append(watch)
            }
        }
        // No await since `watches` was read for evaluation, so this keeps any added or stopped meanwhile.
        watches = remaining
        armedShell = armedShell.intersection(Set(watches.map(\.id)))
        if watches.isEmpty { timer?.invalidate(); timer = nil }
    }

    private func notify(_ message: String, id: UUID) {
        let content = UNMutableNotificationContent()
        content.title = "Watch"
        content.body = message
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil))
    }

    /// Running apps' names plus the title of every window of every regular app. Window titles need
    /// the Accessibility permission Zeus already asks for. Without it, or when any app does not
    /// answer, the snapshot is marked unobserved, so a watch waits rather than reporting "gone"
    /// from titles it could not read.
    private static func snapshot(shellTests: [String: Bool]) -> FakeMacSnapshot {
        let front = NSWorkspace.shared.frontmostApplication
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var titles = apps.compactMap(\.localizedName)
        var observed = AXIsProcessTrusted()
        if observed {
            for app in apps {
                guard let windowTitles = windowTitles(of: app) else { observed = false; break }
                titles.append(contentsOf: windowTitles)
            }
        }
        let frontTitle = front.flatMap { app in observed ? focusedTitle(of: app) : nil } ?? ""
        return FakeMacSnapshot(frontApp: front?.localizedName ?? "", frontWindowTitle: frontTitle,
                               shellTests: shellTests, openTitles: titles, windowsObserved: observed)
    }

    /// Titles of all of one app's windows, or nil when the app could not be read.
    private static func windowTitles(of app: NSRunningApplication) -> [String]? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        var windows: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows)
        // An app with no window list (menu-bar style apps) simply has no windows to match.
        if status == .noValue || status == .attributeUnsupported { return [] }
        guard status == .success, let list = windows as? [AXUIElement] else { return nil }
        // One unreadable title makes the whole app unobserved, so a watch never reads it as "gone".
        var titles: [String] = []
        for window in list {
            var title: CFTypeRef?
            let read = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
            if read == .noValue || read == .attributeUnsupported { continue }
            guard read == .success else { return nil }
            if let text = title as? String { titles.append(text) }
        }
        return titles
    }

    private static func focusedTitle(of app: NSRunningApplication) -> String {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return "" }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(unsafeBitCast(window, to: AXUIElement.self), kAXTitleAttribute as CFString, &title) == .success else { return "" }
        return title as? String ?? ""
    }

    /// Holds the child so the timeout can end it from another queue.
    private final class TestProcess: @unchecked Sendable {
        let process = Process()
    }

    /// Exit 0 within 3 seconds; anything else (including a timeout) is false.
    nonisolated private static func runTest(_ command: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let child = TestProcess()
                child.process.executableURL = URL(fileURLWithPath: "/bin/sh")
                child.process.arguments = ["-c", command]
                child.process.standardOutput = FileHandle.nullDevice
                child.process.standardError = FileHandle.nullDevice
                do { try child.process.run() } catch {
                    continuation.resume(returning: false)
                    return
                }
                let killer = DispatchWorkItem { if child.process.isRunning { child.process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: killer)
                child.process.waitUntilExit()
                killer.cancel()
                continuation.resume(returning: child.process.terminationStatus == 0)
            }
        }
    }
}
