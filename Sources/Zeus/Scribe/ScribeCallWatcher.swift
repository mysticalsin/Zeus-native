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
    /// Known call apps that are running (or a browser showing a Meet tab) whether or not they use the
    /// microphone right now. A call app that stopped capturing while muted still shows up here.
    var runningCallApps: [ScribeDetectedCall] = []
    /// A known call app is capturing or browser call evidence exists, even when a process couldn't be read.
    /// Never used to withhold the microphone; it only drives the "shared" note.
    var callPresent: Bool = false
    /// Any other process capturing the microphone right now, identified or not. Never withholds Zeus's microphone.
    var externalInputDetected: Bool = false
    /// Whether each running call app's call window is on screen. Unknown unless window titles are readable.
    var callWindows: [ScribeCallApp: ScribeCallWindowState] = [:]
}

/// Finds calls in progress: a known call app (or a browser on a Meet tab) that is capturing the microphone.
/// A running call app alone does not prove a call (Teams is always open), so `calls` follows microphone
/// capture. Another app using the microphone never withholds Zeus's own microphone; the mute detector only
/// reports it.
enum ScribeCallProbe {
    static func scan() -> ScribeCallScan {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let titles = windowTitlesByPID()
        let running = runningApps(titles: titles)
        let reads = inputReads()
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
        return ScribeCallScan(calls: calls, runningCallApps: runningCallApps(from: running),
                              callPresent: callPresent, externalInputDetected: externalInput,
                              callWindows: callWindows(running: running, titles: titles))
    }

    /// Call window state per call app. A native app is judged by its own window titles; Meet by whether any
    /// browser shows a Meet tab. Hidden or missing titles are "unknown", which never ends a recording.
    private static func callWindows(
        running: [ScribeRunningApp],
        titles: [pid_t: (titles: [String], numbers: [Int], complete: Bool)]?
    ) -> [ScribeCallApp: ScribeCallWindowState] {
        var states: [ScribeCallApp: ScribeCallWindowState] = [:]
        for app in running where !ScribeCallDetection.isBrowser(app.bundleID) {
            guard let kind = ScribeCallDetection.identify(bundleID: app.bundleID) else { continue }
            guard let read = titles?[app.pid] else { states[kind] = .unknown; continue }
            states[kind] = ScribeCallWindow.state(app: kind, titles: read.titles, complete: read.complete)
        }
        let browsers = running.filter { ScribeCallDetection.isBrowser($0.bundleID) }
        if browsers.contains(where: { ScribeCallDetection.identify(bundleID: $0.bundleID, windowTitles: $0.windowTitles ?? []) == .meet }) {
            states[.meet] = .present
        } else {
            states[.meet] = browsers.allSatisfy { $0.windowTitles != nil && $0.titlesComplete } ? .gone : .unknown
        }
        return states
    }

    /// Running GUI apps. Browsers carry their window titles, read once for all windows (nil when the list
    /// couldn't be read; empty when titles are hidden).
    private static func runningApps(titles: [pid_t: (titles: [String], numbers: [Int], complete: Bool)]?) -> [ScribeRunningApp] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
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

/// What the watcher needs from the microphone listeners; a test supplies its own.
protocol ScribeMicObserving: AnyObject {
    func start()
    func stop()
}

extension ScribeMicActivityObserver: ScribeMicObserving {}

/// Watches for a call in progress or a meeting about to start and hands each reading to the meeting-start
/// machine, which decides what the card says.
/// It runs only when a meeting is near (`ScribeDetectorPlan`). Off with the machine idle: nothing runs, no timer,
/// no microphone listeners, no calendar reads. Otherwise the microphone listeners and one wake-up two minutes
/// before the next calendar meeting; the 5 s poll is only the backup while a meeting is near. It starts at launch
/// unless the choice is Off and follows the choice at once. It never asks for any permission: calendar events
/// are read only when full access was already granted elsewhere.
@MainActor
final class ScribeCallWatcher {
    /// What the watcher reads and does outside itself. The shipped ports are the real clock, setting, calendar,
    /// probe and machine; a test replaces each.
    struct Ports {
        var mode: () -> ScribeAutoStartMode
        /// The meeting-start machine has nothing in hand: no card, no start, no recording to follow.
        var machineIdle: () -> Bool
        /// The meetings from a little before `now` to `lookAhead` after it.
        var slots: (Date, TimeInterval) -> [ScribeCalendarSlot]
        var scan: @MainActor () async -> ScribeCallScan
        var ingest: (ScribeCallScan, [ScribeCalendarSlot], Date) -> Void
        /// Forgets the machine when the detector stops.
        var reset: () -> Void
        var terminated: (ScribeCallProcessIdentity) -> Void
        var now: () -> Date
    }

    typealias MicObserverFactory = (@escaping @MainActor @Sendable () -> Void) -> ScribeMicObserving

    static let shared = ScribeCallWatcher(
        ports: Ports(
            mode: { ScribeAutoStartMode.current() },
            machineIdle: { ScribeAutoStartController.shared.isIdle },
            slots: { now, lookAhead in
                ScribeCalendarReader.shared.slots(from: now.addingTimeInterval(-ScribeMeetingStartPolicy.lateWindow),
                                                  to: now.addingTimeInterval(lookAhead))
            },
            scan: { await Task.detached(priority: .utility) { ScribeCallProbe.scan() }.value },
            ingest: { scan, slots, now in ScribeAutoStartController.shared.ingest(scan: scan, slots: slots, date: now) },
            reset: { ScribeAutoStartController.shared.stop() },
            terminated: { ScribeController.shared.boundCallApplicationDidTerminate($0) },
            now: { Date() }),
        micObserver: { onChange in ScribeMicActivityObserver(onChange: onChange) },
        scheduler: ScribeRunLoopScheduler(),
        workspaceCenter: NSWorkspace.shared.notificationCenter,
        notificationCenter: .default)

    /// The backup poll while a meeting is near.
    private static let interval: TimeInterval = 5
    /// The longest one scan may take. A probe that hangs is given up on, so the gate cannot stay in `scanning`.
    static let scanTimeout: TimeInterval = 10

    private let ports: Ports
    private let makeMicObserver: MicObserverFactory
    private let scheduler: ScribeOneShotScheduling
    private let workspaceCenter: NotificationCenter
    private let notificationCenter: NotificationCenter

    private var running = false
    /// Bumped each time the detector stops, so a scan that began before the stop is dropped when it ends.
    private var generation = 0
    private var gate = ScribeScanGate()
    /// The scan in flight, by number; nil when none is. A reading for any other number is dropped, so a probe
    /// that answers after it was given up on cannot be mistaken for the scan that replaced it.
    private var scanNumber = 0
    private var scanInFlight: Int?
    private var latestCalls: [ScribeDetectedCall] = []
    private var lastMicActive = false
    private var lastSlots: [ScribeCalendarSlot] = []
    private(set) var plan: ScribeDetectorPlan = .stopped
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var micObserver: ScribeMicObserving?

    init(ports: Ports, micObserver: @escaping MicObserverFactory, scheduler: ScribeOneShotScheduling,
         workspaceCenter: NotificationCenter, notificationCenter: NotificationCenter) {
        self.ports = ports
        self.makeMicObserver = micObserver
        self.scheduler = scheduler
        self.workspaceCenter = workspaceCenter
        self.notificationCenter = notificationCenter
    }

    var isRunning: Bool { running }

    /// True while the watcher runs and a call in progress has a browser as its main process. Read only.
    var browserCallPresent: Bool {
        isRunning && latestCalls.contains { $0.pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }.map(ScribeCallDetection.isBrowser) ?? false }
    }

    /// Brings the detector in line with the "When a meeting starts" choice and the machine. Called at launch and
    /// at every change of the choice: the plan decides between stopping and reading now.
    func follow() {
        let wanted = ScribeDetectorPlan.plan(mode: ports.mode(), machineIdle: ports.machineIdle(),
                                             micActive: lastMicActive, slots: lastSlots, now: ports.now())
        guard wanted != .stopped else {
            halt()
            return
        }
        begin()
        wake()
    }

    /// Reads fresh signals now (the call-ended timer and microphone wake-ups ask for this).
    func pollNow() { wake() }

    /// Bind only a positively detected native app instance. A browser process owns many tabs and is not
    /// a call identity; calendar/manual starts likewise have no automatic end adapter.
    func recordingIdentity(for kind: ScribeCallApp) -> ScribeCallProcessIdentity? {
        guard let call = latestCalls.first(where: { $0.app == kind }), let pid = call.pid,
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

    // MARK: Running

    /// Installs the listeners. Nothing here reads the calendar or the microphone: the first scan does.
    private func begin() {
        guard !running else { return }
        running = true
        observe(workspaceCenter, NSWorkspace.didTerminateApplicationNotification) { [weak self] notification in
            // Notification/userInfo are not Sendable. Read the OS object on its callback queue and
            // carry only immutable identity values into actor isolation, as for the music observers.
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier > 0, let bundle = app.bundleIdentifier, let launched = app.launchDate else { return }
            let identity = ScribeCallProcessIdentity(pid: app.processIdentifier, bundleID: bundle,
                                                    launchedAt: launched.timeIntervalSince1970)
            MainActor.assumeIsolated { self?.ports.terminated(identity) }
        }
        observe(workspaceCenter, NSWorkspace.didWakeNotification) { [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        }
        // A changed calendar moves the next meeting, so the wake-up is set again after the next scan.
        observe(notificationCenter, .EKEventStoreChanged) { [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        }
        let observer = makeMicObserver { [weak self] in self?.wake() }
        observer.start()
        micObserver = observer
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @Sendable (Notification) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: handler)))
    }

    /// Takes everything down. A scan still in flight is dropped when it ends.
    private func halt() {
        generation += 1
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        micObserver?.stop()
        micObserver = nil
        scheduler.schedule(after: nil) {}
        gate = ScribeScanGate()
        scanInFlight = nil
        plan = .stopped
        latestCalls = []
        lastMicActive = false
        lastSlots = []
        let wasRunning = running
        running = false
        // Off means the machine is idle, so this only clears what it remembers of the last call.
        if wasRunning { ports.reset() }
    }

    /// One reason to read the signals now: the wake-up, the poll, a microphone change, the calendar or the setting.
    private func wake() {
        guard running, gate.handle(.wake) == .scan else { return }
        scan()
    }

    private func scan() {
        let started = generation
        scanNumber += 1
        let number = scanNumber
        scanInFlight = number
        Task { @MainActor [weak self] in
            // The detector may have stopped since the wake: then nothing is read.
            guard let self, running, started == generation else { return }
            let now = ports.now()
            let slots = ports.slots(now, ScribeDetectorPlan.lookAhead)
            // The one scheduler slot is free while a scan runs; `applyPlan` takes it back when the scan ends. If the
            // probe never answers, this fires and the scan ends as an empty reading.
            scheduler.schedule(after: Self.scanTimeout) { [weak self] in
                self?.finish(ScribeCallScan(calls: []), slots: slots, now: now, generation: started, number: number)
            }
            let reading = await ports.scan()
            finish(reading, slots: slots, now: now, generation: started, number: number)
        }
    }

    private func finish(_ scan: ScribeCallScan, slots: [ScribeCalendarSlot], now: Date, generation started: Int,
                        number: Int) {
        guard running, started == generation, scanInFlight == number else { return }
        scanInFlight = nil
        latestCalls = scan.calls
        lastMicActive = !scan.calls.isEmpty
        lastSlots = slots
        // The meeting-start machine owns every card: the heads-up before a calendar meeting, a meeting that has
        // started and a call in progress. It asks, starts by itself or stays quiet by the "When a meeting
        // starts" setting.
        ports.ingest(scan, slots, now)
        let again = gate.handle(.finished) == .scan
        applyPlan()
        // A wake that came during the scan reads once more.
        if again, running { self.scan() }
    }

    /// Sets the one wake-up the plan asks for, after the machine has seen the scan.
    private func applyPlan() {
        let now = ports.now()
        plan = ScribeDetectorPlan.plan(mode: ports.mode(), machineIdle: ports.machineIdle(),
                                       micActive: lastMicActive, slots: lastSlots, now: now)
        switch plan {
        case .stopped:
            halt()
        case .polling:
            scheduler.schedule(after: Self.interval) { [weak self] in self?.wake() }
        case .listening(let wakeAt):
            scheduler.schedule(after: wakeAt.map { max(0, $0.timeIntervalSince(now)) }) { [weak self] in self?.wake() }
        }
    }
}
