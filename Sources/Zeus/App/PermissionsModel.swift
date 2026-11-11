import AppKit
import AVFoundation
import Observation
import Speech
import EventKit
import ApplicationServices
import ZeusCore

/// macOS privacy access ZEUS can ask for, plus Claude Code and Chrome connections.
@MainActor
@Observable
final class PermissionsModel {
    enum Kind: String, CaseIterable, Identifiable {
        case microphone = "Microphone"
        case speech = "Speech recognition"
        case accessibility = "Accessibility (hotkey)"
        case camera = "Camera"
        case screen = "Screen Recording"
        case calendar = "Calendar"
        case reminders = "Reminders"
        case automation = "Automation (Music, Spotify)"
        var id: String { rawValue }

        var settingsURL: URL? {
            let pane: String = switch self {
            case .microphone: "Privacy_Microphone"
            case .speech: "Privacy_SpeechRecognition"
            case .accessibility: "Privacy_Accessibility"
            case .camera: "Privacy_Camera"
            case .screen: "Privacy_ScreenCapture"
            case .calendar: "Privacy_Calendars"
            case .reminders: "Privacy_Reminders"
            case .automation: "Privacy_Automation"
            }
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        }
    }

    private(set) var granted: [Kind: Bool] = [:]
    /// True while Apple Events consent is still being determined (check in flight or last attempt timed out).
    private(set) var automationPending = false
    /// True while the macOS consent sheet for Automation is up (the Allow button waits).
    private(set) var automationAsking = false
    /// Why the last Automation Allow could not ask (no target app was running); nil otherwise.
    var automationMessage: String?
    private(set) var claudeHooksInstalled = ClaudeHookInstaller.isInstalled()
    var hookMessage: String?
    private(set) var chromeHostInstalled = ChromeInstaller.isInstalled()
    private(set) var chromeConnected = false
    var chromeMessage: String?

    private static let screenRequestKey = "permissions.screenCapture.requested"

    /// Explicit permission boundary. Tests inject state and requests instead of displaying OS prompts.
    @MainActor
    struct CaptureAccess {
        var camera: () -> PermissionState
        var screen: () -> PermissionState
        var requestCamera: () async -> Void

        static var live: Self {
            Self(
                camera: { CapturePermissions.cameraState(authorizationRaw: AVCaptureDevice.authorizationStatus(for: .video).rawValue) },
                screen: {
                    CapturePermissions.screenRecordingState(
                        preflightGranted: CGPreflightScreenCaptureAccess(),
                        requestAttempted: UserDefaults.standard.bool(forKey: PermissionsModel.screenRequestKey))
                },
                requestCamera: { _ = await AVCaptureDevice.requestAccess(for: .video) }
            )
        }
    }

    @ObservationIgnored private let captureAccess: CaptureAccess

    var cameraPermissionState: PermissionState {
        captureAccess.camera()
    }

    var screenPermissionState: PermissionState {
        captureAccess.screen()
    }

    /// Silent E2E: `zeus debug permissions`.
    var capturePermissionsReport: String {
        CapturePermissions.debugReport(camera: cameraPermissionState, screen: screenPermissionState)
    }

    var allGranted: Bool { Kind.allCases.allSatisfy { granted[$0] == true } }

    init(captureAccess: CaptureAccess = .live) {
        self.captureAccess = captureAccess
        Automation.onCacheUpdated = { [weak self] in self?.refreshAutomationOnly() }
    }

    func refresh() {
        granted[.microphone] = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        granted[.speech] = SFSpeechRecognizer.authorizationStatus() == .authorized
        granted[.accessibility] = AXIsProcessTrusted()
        granted[.camera] = cameraPermissionState == .authorized
        granted[.screen] = screenPermissionState == .authorized
        granted[.calendar] = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        granted[.reminders] = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        refreshAutomationOnly()
        claudeHooksInstalled = ClaudeHookInstaller.isInstalled()
        chromeHostInstalled = ChromeInstaller.isInstalled()
        Task { chromeConnected = await ChromeBridge.isConnected() }
    }

    private func refreshAutomationOnly() {
        Automation.scheduleChecksForRunningPlayers()
        granted[.automation] = Automation.allowedAny
        automationPending = Automation.anyPending
        if granted[.automation] == true { automationMessage = nil }
    }

    /// Push-to-talk works (the key is seen, ZEUS can hear and transcribe). Screen Recording only
    /// adds screenshots, so it isn't required.
    var voiceReady: Bool {
        granted[.microphone] == true && granted[.speech] == true && granted[.accessibility] == true
    }

    // Each permission is asked for when its feature is first used (HIG › Privacy), from the
    // setup window or the first push-to-talk, never all at once at launch.

    func requestAccessibility() {
        if !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        refresh()
    }

    /// Microphone, then speech recognition (each system prompt appears only once).
    func requestVoice() async {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await SystemAuthorization.requestSpeechRecognition()
        }
        refresh()
    }

    var voiceUndetermined: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
            || SFSpeechRecognizer.authorizationStatus() == .notDetermined
    }

    func requestScreen() {
        guard !CGPreflightScreenCaptureAccess() else { refresh(); return }
        UserDefaults.standard.set(true, forKey: Self.screenRequestKey)
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }

    func requestCamera() async {
        if cameraPermissionState == .notDetermined {
            await captureAccess.requestCamera()
        }
        granted[.camera] = cameraPermissionState == .authorized
    }

    /// The only place a macOS permission prompt is raised: setup, or a Turn On click in
    /// Settings > Permissions. Already decided (denied) opens System Settings instead.
    func request(_ kind: Kind) {
        switch kind {
        case .accessibility:
            if AXIsProcessTrusted() { open(kind) } else { requestAccessibility() }
        case .microphone, .speech:
            if voiceUndetermined { Task { await requestVoice() } } else { open(kind) }
        case .camera:
            switch cameraPermissionState {
            case .authorized: open(kind)
            case .notDetermined: Task { await requestCamera() }
            case .denied: open(kind)
            }
        case .screen:
            switch screenPermissionState {
            case .authorized: open(kind)
            case .notDetermined: requestScreen()
            case .denied: open(kind)
            }
        case .calendar, .reminders:
            let type: EKEntityType = kind == .calendar ? .event : .reminder
            guard EKEventStore.authorizationStatus(for: type) == .notDetermined else { return open(kind) }
            Task { @MainActor in
                let store = EKEventStore()
                if kind == .calendar { _ = try? await store.requestFullAccessToEvents() }
                else { _ = try? await store.requestFullAccessToReminders() }
                self.refresh()
            }
        case .automation:
            requestAutomation()
        }
    }

    /// Automation can only be asked about a running app. With none running, say so instead of doing nothing;
    /// otherwise the consent sheet is raised off the main actor (it stays up until the person answers).
    func requestAutomation() {
        guard !automationAsking else { return }
        let running = Automation.players.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
        guard running else {
            automationMessage = "Open Music or Spotify, then press Allow."
            refresh()
            return
        }
        automationMessage = nil
        automationAsking = true
        Task { @MainActor in
            let result = await Automation.askAsync()
            automationAsking = false
            if result == false { open(.automation) }
            refresh()
        }
    }

    /// Wording for an inline hint when a feature needs a permission that isn't on yet.
    static func hint(_ kind: Kind) -> String {
        let name = switch kind {
        case .accessibility: "Accessibility"
        case .automation: "Automation"
        case .speech: "Speech"
        case .camera: "Camera"
        case .screen: "Screen Recording"
        default: kind.rawValue
        }
        return "Allow \(name) in Settings"
    }

    func open(_ kind: Kind) {
        if let url = kind.settingsURL { NSWorkspace.shared.open(url) }
    }

    func connectClaudeCode() {
        do {
            let backup = try ClaudeHookInstaller.install()
            hookMessage = backup.map { "Connected. Backup: \($0.lastPathComponent)" } ?? "Connected."
        } catch {
            hookMessage = error.localizedDescription
        }
        refresh()
    }

    func disconnectClaudeCode() {
        do {
            try ClaudeHookInstaller.uninstall()
            hookMessage = "Disconnected. Other hooks were left as they were."
        } catch {
            hookMessage = error.localizedDescription
        }
        refresh()
    }

    func connectChrome() {
        do {
            try ChromeInstaller.install()
            chromeMessage = "In Chrome: turn on Developer mode, click Load unpacked and pick the ChromeExtension folder that just opened."
            ChromeInstaller.showLoadUnpacked()
        } catch {
            chromeMessage = error.localizedDescription
        }
        refresh()
    }

    func disconnectChrome() {
        do {
            try ChromeInstaller.uninstall()
            chromeMessage = "Disconnected. You can remove the Zeus extension in chrome://extensions."
        } catch {
            chromeMessage = error.localizedDescription
        }
        refresh()
    }
}

/// Apple Events consent for the music players. Status checks never prompt; `ask()` does, and is
/// only called from setup or Settings > Permissions.
enum Automation {
    /// Music players, plus the presentation apps the teleprompter reads notes from.
    static let players = ["com.apple.Music", "com.spotify.client", "com.apple.iWork.Keynote", "com.microsoft.Powerpoint"]

    /// For the teleprompter: whether ZEUS may script this app right now, never asking.
    static func gate(_ bundleID: String) -> AutomationGate.Status {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return .appNotRunning }
        switch cachedStatus(bundleID) {
        case .granted: return .granted
        case .denied(let code) where code == OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        case .denied: return .denied
        case .pending: return .notAsked
        }
    }
    private static let askedKey = "permissions.automation.asked"

    /// True when macOS already lets ZEUS control this app (never shows a prompt).
    static func allowed(_ bundleID: String) -> Bool {
        if case .granted = cachedStatus(bundleID) { return true }
        return false
    }

    /// Names for the apps in `players`, for "Allowed for Music".
    static func name(_ bundleID: String) -> String {
        switch bundleID {
        case "com.apple.Music": "Music"
        case "com.spotify.client": "Spotify"
        case "com.apple.iWork.Keynote": "Keynote"
        case "com.microsoft.Powerpoint": "PowerPoint"
        default: bundleID
        }
    }

    /// One key per target: consent survives the app quitting, and a refusal seen later clears it (see `remember`).
    private static func grantKey(_ bundleID: String) -> String { askedKey + ".granted." + bundleID }

    /// The apps ZEUS may script, by a current successful check only. An old grant is not enough: it can
    /// have been revoked in System Settings while the app was closed (see `unverifiedTargets`).
    static var allowedTargets: [String] {
        players.filter { allowed($0) }
    }

    /// Apps allowed in the past that no current check confirms (usually not running). Shown as "not verified".
    static var unverifiedTargets: [String] {
        players.filter { !allowed($0) && UserDefaults.standard.bool(forKey: grantKey($0)) }
    }

    /// Any target allowed. Partial access is possible: use `allowedTargets` to say which.
    static var allowedAny: Bool { !allowedTargets.isEmpty }

    /// Keeps a grant for an app that is not running, and forgets it once macOS reports it revoked (or never given).
    private static func remember(_ bundleID: String, _ code: OSStatus) {
        let defaults = UserDefaults.standard
        if code == noErr {
            defaults.set(true, forKey: grantKey(bundleID))
        } else if code == OSStatus(errAEEventNotPermitted) || code == OSStatus(errAEEventWouldRequireUserConsent) {
            defaults.removeObject(forKey: grantKey(bundleID))
        }
    }

    static var anyPending: Bool {
        players.contains { if case .pending = cachedStatus($0) { return true }; return false }
    }

    /// Asks for each running player. Nil when no player is running to ask about.
    @discardableResult
    static func ask() -> Bool? {
        let running = players.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
        guard !running.isEmpty else { return nil }
        var codes: [String: OSStatus] = [:]
        for id in running { codes[id] = promptStatus(id) }
        for (id, code) in codes { storeResolved(id, code) }
        return codes.values.contains(noErr)
    }

    /// `ask()` without holding the caller: the consent sheet can stay up until the person answers.
    static func askAsync() async -> Bool? {
        let running = players.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
        guard !running.isEmpty else { return nil }
        let codes = await Task.detached(priority: .userInitiated) { () -> [String: OSStatus] in
            var codes: [String: OSStatus] = [:]
            for id in running { codes[id] = promptStatus(id) }
            return codes
        }.value
        for (id, code) in codes { storeResolved(id, code) }
        return codes.values.contains(noErr)
    }

    /// Starts background checks for running targets (never blocks the caller).
    static func scheduleChecksForRunningPlayers() {
        for id in players where !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
            scheduleCheck(id)
        }
    }

    /// Called on the main actor when a background check finishes.
    nonisolated(unsafe) static var onCacheUpdated: (@MainActor () -> Void)?

    /// Unit tests replace the AppleEvents call (never hit the network or real TCC).
    nonisolated(unsafe) static var testStatusProvider: ((String, Bool) -> OSStatus)?

    private enum Cached {
        case granted
        case denied(OSStatus)
        case pending
    }

    private struct Entry {
        enum State { case resolved(OSStatus), pending }
        var state: State
        var updatedAt: Date
    }

    nonisolated(unsafe) private static var cache: [String: Entry] = [:]
    nonisolated(unsafe) private static var inFlight: Set<String> = []
    private static let cacheLock = NSLock()
    /// Status checks are bounded: macOS can block AEDeterminePermission... when a consent sheet is up.
    static let checkTimeout: TimeInterval = 1.0
    private static let resolvedTTL: TimeInterval = 20
    private static let pendingRecheck: TimeInterval = 5

    private static func cachedStatus(_ bundleID: String) -> Cached {
        scheduleCheck(bundleID)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let entry = cache[bundleID] else { return .pending }
        switch entry.state {
        case .resolved(let code):
            guard Date().timeIntervalSince(entry.updatedAt) < resolvedTTL else { return .pending }
            return code == noErr ? .granted : .denied(code)
        case .pending:
            return .pending
        }
    }

    private static func storeResolved(_ bundleID: String, _ code: OSStatus) {
        cacheLock.lock()
        cache[bundleID] = Entry(state: .resolved(code), updatedAt: Date())
        cacheLock.unlock()
        remember(bundleID, code)
    }

    private static func storePending(_ bundleID: String) {
        cacheLock.lock()
        cache[bundleID] = Entry(state: .pending, updatedAt: Date())
        cacheLock.unlock()
    }

    private static func scheduleCheck(_ bundleID: String) {
        cacheLock.lock()
        if inFlight.contains(bundleID) { cacheLock.unlock(); return }
        if let entry = cache[bundleID] {
            let age = Date().timeIntervalSince(entry.updatedAt)
            switch entry.state {
            case .resolved where age < resolvedTTL: cacheLock.unlock(); return
            case .pending where age < pendingRecheck: cacheLock.unlock(); return
            default: break
            }
        }
        inFlight.insert(bundleID)
        cacheLock.unlock()

        DispatchQueue.global(qos: .utility).async {
            let box = StatusBox()
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                box.value = performStatus(bundleID, ask: false)
                done.signal()
            }
            let finishedInTime = done.wait(timeout: .now() + checkTimeout) == .success
            if !finishedInTime {
                storePending(bundleID)
                _ = done.wait(timeout: .now() + 30)
            } else {
                storeResolved(bundleID, box.value)
            }
            cacheLock.lock()
            inFlight.remove(bundleID)
            cacheLock.unlock()
            if let onCacheUpdated { DispatchQueue.main.async { onCacheUpdated() } }
        }
    }

    /// Prompting path: only from an explicit Allow click (may block until the person answers).
    private static func promptStatus(_ bundleID: String) -> OSStatus {
        performStatus(bundleID, ask: true)
    }

    private static func performStatus(_ bundleID: String, ask: Bool) -> OSStatus {
        if let testStatusProvider { return testStatusProvider(bundleID, ask) }
        return rawStatus(bundleID, ask: ask)
    }

    private final class StatusBox: @unchecked Sendable { var value: OSStatus = -1 }

    private static func rawStatus(_ bundleID: String, ask: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        guard AECreateDesc(DescType(typeApplicationBundleID), bytes, bytes.count, &target) == noErr else { return -1 }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
    }

    /// Test hook: reset cache and in-flight state between tests.
    static func resetCacheForTesting() {
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            cacheLock.lock()
            let busy = !inFlight.isEmpty
            cacheLock.unlock()
            if !busy { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        cacheLock.lock()
        cache.removeAll()
        inFlight.removeAll()
        cacheLock.unlock()
        testStatusProvider = nil
    }
}

/// Global key and mouse-posting features wait for Accessibility instead of triggering a macOS
/// prompt mid-use. Untrusted, the work is retried every 3 s (a cheap check) until it is granted
/// from setup or Settings > Permissions.
@MainActor
enum AccessibilityGate {
    private static var waiting: [() -> Void] = []
    private static var timer: Timer?

    static var trusted: Bool { AXIsProcessTrusted() }

    static func whenTrusted(_ work: @escaping () -> Void) {
        if trusted { work(); return }
        waiting.append(work)
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard trusted else { return }
                timer?.invalidate(); timer = nil
                let ready = waiting; waiting.removeAll()
                NSLog("[ZEUS] permissions: Accessibility granted, starting %d key features", ready.count)
                ready.forEach { $0() }
            }
        }
    }
}
