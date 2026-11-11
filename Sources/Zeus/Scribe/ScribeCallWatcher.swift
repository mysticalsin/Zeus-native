import AppKit
import CoreAudio
import CoreGraphics
import EventKit
import Foundation
import ZeusCore

/// Small typed readers over CoreAudio's property API.
enum ScribeCoreAudio {
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func readUInt32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> UInt32? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func readObjectID(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> AudioObjectID? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              value != kAudioObjectUnknown else { return nil }
        return value
    }

    static func readString(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

struct ScribeDetectedCall: Equatable, Sendable {
    let app: ScribeCallApp
    /// The app's main process (not a helper) when it is running; used to read its mute button.
    let pid: pid_t?
}

struct ScribeCallScan: Equatable, Sendable {
    /// Calls in progress: a known call app (or a browser on a Meet tab) capturing the microphone.
    var calls: [ScribeDetectedCall]
    /// What the mute detector needs: incomplete when any process couldn't be read, browser state unknown unless
    /// window titles were read. Never "no call" by default.
    var inputScan: ScribeInputScan
    /// Known call apps that are running (or a browser showing a Meet tab) whether or not they use the
    /// microphone right now. A call app that stopped capturing while muted still shows up here.
    var runningCallApps: [ScribeDetectedCall] = []
    /// A known call app is running or browser call evidence exists, even when `inputScan` is `.incomplete`
    /// (an unreadable process). Never used to admit the microphone.
    var callPresent: Bool = false
    /// Includes unsupported owners: releasing input later must not silently restore Zeus's microphone.
    var externalInputDetected: Bool = false
}

/// Finds calls in progress: a known call app (or a browser on a Meet tab) that is capturing the microphone.
/// A running call app alone does not prove a call (Teams is always open), so `calls` follows microphone
/// capture; `inputScan` and `runningCallApps` are reported for the mute detector, which fails closed on them.
enum ScribeCallProbe {
    static func scan() -> ScribeCallScan {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let running = runningApps()
        let reads = inputReads()
        let inputScan = reads.map { ScribeScanReducer.reduce(reads: $0, running: running, ownPID: ownPID) } ?? .incomplete
        var calls: [ScribeDetectedCall] = []
        for case .input(let pid, let bundleID) in reads ?? [] where pid != ownPID {
            guard let appBundleID = ScribeCallDetection.appBundleID(for: bundleID) else { continue }
            let main = running.first { $0.bundleID == appBundleID }
            let titles = ScribeCallDetection.isBrowser(bundleID) ? (main?.windowTitles ?? []) : []
            if let app = ScribeCallDetection.identify(bundleID: bundleID, windowTitles: titles),
               !calls.contains(where: { $0.app == app }) {
                calls.append(ScribeDetectedCall(app: app, pid: main?.pid ?? (pid > 0 ? pid : nil)))
            }
        }
        calls.sort { rank($0.app) != rank($1.app) ? rank($0.app) < rank($1.app) : ScribeCallDetection.displayName($0.app) < ScribeCallDetection.displayName($1.app) }
        let callPresent = ScribeScanReducer.callPresence(reads: reads ?? [], running: running, ownPID: ownPID)
        let externalInput = (reads ?? []).contains { $0.isExternalInput(excluding: ownPID) }
        return ScribeCallScan(calls: calls, inputScan: inputScan, runningCallApps: runningCallApps(from: running),
                              callPresent: callPresent, externalInputDetected: externalInput)
    }

    /// Running GUI apps. Browsers carry their window titles, read once for all windows (nil when the list
    /// couldn't be read; empty when titles are hidden).
    private static func runningApps() -> [ScribeRunningApp] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let titles = windowTitlesByPID()
        return NSWorkspace.shared.runningApplications.compactMap { application -> ScribeRunningApp? in
            guard !application.isTerminated, application.processIdentifier != ownPID,
                  let bundleID = application.bundleIdentifier else { return nil }
            let pid = application.processIdentifier
            guard ScribeCallDetection.isBrowser(bundleID) else {
                return ScribeRunningApp(pid: pid, bundleID: bundleID, windowTitles: nil)
            }
            // A failed window-list read, or a process with no windows listed, is unavailable (nil / empty).
            let read = titles?[pid]
            return ScribeRunningApp(
                pid: pid, bundleID: bundleID,
                windowTitles: titles == nil ? nil : (read?.titles ?? []),
                windowNumbers: read?.numbers ?? [],
                titlesComplete: read?.complete ?? false
            )
        }
    }

    /// Running call apps, found from the workspace rather than from audio activity.
    private static func runningCallApps(from running: [ScribeRunningApp]) -> [ScribeDetectedCall] {
        var found: [ScribeDetectedCall] = []
        for app in running {
            guard let identified = ScribeCallDetection.identify(bundleID: app.bundleID, windowTitles: app.windowTitles ?? []),
                  !found.contains(where: { $0.app == identified }) else { continue }
            found.append(ScribeDetectedCall(app: identified, pid: app.pid))
        }
        return found
    }

    private static func rank(_ app: ScribeCallApp) -> Int {
        switch app {
        case .teams: return 0
        case .zoom: return 1
        case .meet: return 2
        case .other: return 3
        }
    }

    /// One read per CoreAudio process object (Package.swift targets macOS 14.2, which has the process list).
    /// A process whose properties can't be read is `.unreadable`, never dropped: the reducer turns it into an
    /// incomplete scan. Nil when the list itself couldn't be read.
    private static func inputReads() -> [ScribeProcessRead]? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var listAddress = ScribeCoreAudio.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &size) == noErr else { return nil }
        if size == 0 { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &listAddress, 0, nil, &size, &objects) == noErr else { return nil }
        return objects.map { object -> ScribeProcessRead in
            guard let running = ScribeCoreAudio.readUInt32(object, ScribeCoreAudio.address(kAudioProcessPropertyIsRunningInput)) else {
                return .unreadable
            }
            guard running == 1 else { return .idle }
            let bundleID = ScribeCoreAudio.readString(object, ScribeCoreAudio.address(kAudioProcessPropertyBundleID))
            let pid = ScribeCoreAudio.readUInt32(object, ScribeCoreAudio.address(kAudioProcessPropertyPID))
                .flatMap { Int32(exactly: $0) }
            return .activeInput(pid: pid, bundleID: bundleID)
        }
    }

    /// Window titles of every process, by pid. macOS hides other apps' window titles unless Screen Recording is
    /// allowed, so a process may have none; the reducer treats that as "can't tell", never as "no call".
    /// A process with any window whose title or window number (`kCGWindowNumber`) is missing is marked
    /// incomplete. `numbers` runs parallel to `titles`. Nil when the window list couldn't be read.
    private static func windowTitlesByPID() -> [pid_t: (titles: [String], numbers: [Int], complete: Bool)]? {
        guard let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return nil }
        var result: [pid_t: (titles: [String], numbers: [Int], complete: Bool)] = [:]
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32 else { continue }
            var entry = result[pid] ?? (titles: [], numbers: [], complete: true)
            if let name = window[kCGWindowName as String] as? String, !name.isEmpty,
               let number = window[kCGWindowNumber as String] as? Int {
                entry.titles.append(name)
                entry.numbers.append(number)
            } else {
                entry.complete = false
            }
            result[pid] = entry
        }
        return result
    }
}

/// Watches for a call in progress or a meeting about to start, and shows the one-tap popup.
/// Started lazily by the first access to `ScribeController.shared`, never at app launch. It never asks for any
/// permission: calendar events are read only when full access was already granted elsewhere.
@MainActor
final class ScribeCallWatcher {
    static let shared = ScribeCallWatcher()

    private(set) var decision: ScribePromptDecision = .none

    private static let interval: TimeInterval = 5

    private var timer: Timer?
    private var scanning = false
    private var dismissedIDs: Set<String> = []
    private var dismissedApps: Set<ScribeCallApp> = []
    private var dismissedInstances: [ScribeCallApp: ScribeCallProcessIdentity] = [:]
    private var latestCalls: [ScribeDetectedCall] = []
    private var terminationObserver: NSObjectProtocol?
    private lazy var eventStore = EKEventStore()

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            // Notification/userInfo are not Sendable. Read the OS object on its callback queue and
            // carry only immutable identity values into actor isolation, as for the music observers.
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier > 0, let bundle = app.bundleIdentifier, let launched = app.launchDate else { return }
            let identity = ScribeCallProcessIdentity(pid: app.processIdentifier, bundleID: bundle,
                                                    launchedAt: launched.timeIntervalSince1970)
            MainActor.assumeIsolated {
                self?.applicationTerminated(identity)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        // Not synchronously: `start()` runs inside `ScribeController.shared`'s initialiser.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.poll()
        }
    }

    func stop() {
        if let terminationObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver) }
        terminationObserver = nil
        timer?.invalidate()
        timer = nil
        decision = .none
        ScribeCallPopup.shared.hide()
    }

    /// Dismisses this prompt: a calendar slot by id, a detected call until that call ends.
    func dismiss(_ dismissed: ScribePromptDecision) {
        switch dismissed {
        case .upcoming(let slot): dismissedIDs.insert(slot.id)
        case .callDetected(let app):
            dismissedApps.insert(app)
            if let call = latestCalls.first(where: { $0.app == app }), let pid = call.pid,
               let running = NSRunningApplication(processIdentifier: pid), !running.isTerminated {
                dismissedInstances[app] = Self.identity(of: running)
            }
        case .none: break
        }
        if decision == dismissed { decision = .none }
        ScribeCallPopup.shared.hide()
    }

    /// Recording began: the prompt has done its job.
    func recordingDidStart() {
        guard isRunning else { return }
        decision = .none
        ScribeCallPopup.shared.hide()
    }

    /// Bind only a positively detected native app instance. A browser process owns many tabs and is not
    /// a call identity; calendar/manual starts likewise have no automatic end adapter.
    func recordingIdentity(for decision: ScribePromptDecision) -> ScribeCallProcessIdentity? {
        guard case .callDetected(let kind) = decision,
              let call = latestCalls.first(where: { $0.app == kind }), let pid = call.pid,
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              let bundle = app.bundleIdentifier, !ScribeCallDetection.isBrowser(bundle),
              ScribeCallDetection.identify(bundleID: bundle) == kind else { return nil }
        return Self.identity(of: app)
    }

    private static func identity(of app: NSRunningApplication) -> ScribeCallProcessIdentity? {
        guard app.processIdentifier > 0, let bundle = app.bundleIdentifier, let launched = app.launchDate else { return nil }
        return ScribeCallProcessIdentity(pid: app.processIdentifier, bundleID: bundle,
                                        launchedAt: launched.timeIntervalSince1970)
    }

    private func applicationTerminated(_ identity: ScribeCallProcessIdentity) {
        for (kind, dismissed) in dismissedInstances where dismissed == identity {
            dismissedApps.remove(kind)
            dismissedInstances.removeValue(forKey: kind)
        }
        ScribeController.shared.boundCallApplicationDidTerminate(identity)
    }

    private func poll() {
        guard isRunning, !scanning else { return }
        scanning = true
        let now = Date()
        let slots = upcomingSlots(now: now)
        Task.detached(priority: .utility) { [weak self] in
            let scan = ScribeCallProbe.scan()
            await self?.apply(scan: scan, slots: slots, now: now)
        }
    }

    private func apply(scan: ScribeCallScan, slots: [ScribeCalendarSlot], now: Date) {
        scanning = false
        guard isRunning else { return }
        latestCalls = scan.calls
        let detectedApps = scan.calls.map(\.app)
        // Mic disappearance can mean mute. Keep Not now suppressed until a positive app-instance exit;
        // neither an empty/incomplete scan nor a changed browser title proves a new call.
        let next = ScribeCallPrompt.decide(
            now: now,
            upcoming: slots,
            activeCallApp: detectedApps.first { !dismissedApps.contains($0) },
            isRecording: ScribeController.shared.phase.isActive,
            dismissedIDs: dismissedIDs,
            dismissedCallApps: dismissedApps
        )
        guard next != decision else {
            ScribeCallPopup.shared.refresh(now: now)
            return
        }
        decision = next
        if case .none = next {
            ScribeCallPopup.shared.hide()
        } else {
            ScribeCallPopup.shared.present(next, now: now)
        }
    }

    /// Meetings that start within the prompt window. Empty unless calendar access was already granted.
    private func upcomingSlots(now: Date) -> [ScribeCalendarSlot] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let from = now.addingTimeInterval(-ScribeCallPrompt.lateWindow)
        let to = now.addingTimeInterval(ScribeCallPrompt.leadWindow + 60)
        let predicate = eventStore.predicateForEvents(withStart: from, end: to, calendars: nil)
        return eventStore.events(matching: predicate).compactMap { event in
            guard !event.isAllDay, event.status != .canceled, let start = event.startDate else { return nil }
            // A meeting, not a reminder to yourself: it has guests or a call link.
            let hasLink = MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes]) != nil
            guard event.hasAttendees || hasLink else { return nil }
            let base = event.eventIdentifier ?? event.title ?? "event"
            return ScribeCalendarSlot(
                id: "\(base)@\(Int(start.timeIntervalSince1970))",
                title: event.title ?? "Meeting",
                start: start,
                end: event.endDate,
                // Display names only; the slot drops anything that looks like an address.
                attendeeNames: (event.attendees ?? []).filter { !$0.isCurrentUser }.compactMap(\.name)
            )
        }
    }
}
