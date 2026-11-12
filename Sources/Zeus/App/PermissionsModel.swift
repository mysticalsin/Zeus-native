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
    /// The apps ZeusCore may script right now, by name ("Music", "Spotify"); drives the status text.
    private(set) var automationAllowedNames: [String] = []
    /// The allowed names when `automationMessage` was written: a change means the message is out of date.
    private var automationMessageAllowedNames: [String] = []
    private(set) var claudeHooksInstalled = false
    var hookMessage: String?
    private(set) var chromeHostInstalled = false
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
        refreshInstallFlagsInBackground()
    }

    @ObservationIgnored private var installFlagsGeneration: UInt64 = 0

    /// The hook and Chrome host files are read on a background thread: `refresh` runs when Settings
    /// opens and must never wait on the disk. A newer read (or a synchronous one after a click) wins.
    private func refreshInstallFlagsInBackground() {
        installFlagsGeneration &+= 1
        let generation = installFlagsGeneration
        Task { [weak self] in
            let flags = await Task.detached(priority: .userInitiated) {
                (ClaudeHookInstaller.isInstalled(), ChromeInstaller.isInstalled())
            }.value
            guard let self, generation == self.installFlagsGeneration else { return }
            if self.claudeHooksInstalled != flags.0 { self.claudeHooksInstalled = flags.0 }
            if self.chromeHostInstalled != flags.1 { self.chromeHostInstalled = flags.1 }
        }
    }

    /// After Connect or Disconnect (a click that just wrote these files): read them now.
    private func refreshInstallFlagsNow() {
        installFlagsGeneration &+= 1
        claudeHooksInstalled = ClaudeHookInstaller.isInstalled()
        chromeHostInstalled = ChromeInstaller.isInstalled()
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
        refreshInstallFlagsInBackground()
        Task { chromeConnected = await ChromeBridge.isConnected() }
    }

    private func refreshAutomationOnly() {
        Automation.scheduleChecksForRunningPlayers()
        granted[.automation] = Automation.allowedAny
        automationPending = Automation.anyPending
        automationAllowedNames = Automation.allowedTargets.map(Automation.name)
        if automationMessage != nil, automationAllowedNames != automationMessageAllowedNames { automationMessage = nil }
    }

    private func setAutomationMessage(_ text: String?) {
        automationMessage = text
        automationMessageAllowedNames = automationAllowedNames
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
        // Shares the "voice" request with `VoicePermissions.ensure`: a double click or a talk-key press
        // during setup joins the prompt that is up instead of asking macOS again.
        await PermissionPrompts.shared.run("voice") { await VoicePermissions.askForVoice() }
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
            await PermissionPrompts.shared.run("camera") { await self.captureAccess.requestCamera() }
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
            Task { @MainActor in await self.requestEventAccess(kind) }
        case .automation:
            requestAutomation()
        }
    }

    /// Calendar or Reminders full access, one prompt at a time. Returns once macOS has an answer
    /// (Allow all waits for it before the next prompt).
    func requestEventAccess(_ kind: Kind) async {
        await PermissionPrompts.shared.run(kind.rawValue) {
            let store = EKEventStore()
            if kind == .calendar { _ = try? await store.requestFullAccessToEvents() }
            else { _ = try? await store.requestFullAccessToReminders() }
        }
        refresh()
    }

    /// Automation can only be asked about a running app. With none running, say so instead of doing nothing;
    /// otherwise the consent sheet is raised off the main actor (it stays up until the person answers).
    func requestAutomation() {
        guard !automationAsking else { return }
        refreshAutomationOnly()
        let plan = AutomationAllowPlan.plan(targets: Automation.targets, access: Automation.accessByTarget,
                                            running: Automation.runningTargets)
        guard !plan.ask.isEmpty else {
            setAutomationMessage(plan.message)
            if plan.opensAutomationPane { open(.automation) }
            refresh()
            return
        }
        setAutomationMessage(nil)
        automationAsking = true
        Task { @MainActor in
            let granted = await Automation.askAsync(only: plan.ask)
            automationAsking = false
            refresh()
            let after = AutomationAllowPlan.afterAsking(
                targets: Automation.targets.filter { plan.ask.contains($0.id) }, granted: granted, alreadyRefused: plan.refused)
            setAutomationMessage(after.message)
            if after.opensAutomationPane { open(.automation) }
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
        refreshInstallFlagsNow()
        refresh()
    }

    func disconnectClaudeCode() {
        do {
            try ClaudeHookInstaller.uninstall()
            hookMessage = "Disconnected. Other hooks were left as they were."
        } catch {
            hookMessage = error.localizedDescription
        }
        refreshInstallFlagsNow()
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
        refreshInstallFlagsNow()
        refresh()
    }

    func disconnectChrome() {
        do {
            try ChromeInstaller.uninstall()
            chromeMessage = "Disconnected. You can remove the Zeus extension in chrome://extensions."
        } catch {
            chromeMessage = error.localizedDescription
        }
        refreshInstallFlagsNow()
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
    /// The cache model decides which (see `AutomationConsentCache`); a stale check never reaches here.
    private static func perform(_ effects: [AutomationConsentCache.Effect], for bundleID: String) {
        let defaults = UserDefaults.standard
        for effect in effects {
            switch effect {
            case .rememberGrant: defaults.set(true, forKey: grantKey(bundleID))
            case .forgetGrant: defaults.removeObject(forKey: grantKey(bundleID))
            case .startCheck: break
            }
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
        for id in running { promptBegan(id) }
        for id in running { codes[id] = promptStatus(id) }
        for (id, code) in codes { promptAnswered(id, code) }
        return codes.values.contains(noErr)
    }

    /// The apps Settings can ask about, with their names.
    static var targets: [AutomationAllowPlan.Target] { players.map { .init(id: $0, name: name($0)) } }

    static var runningTargets: Set<String> {
        Set(players.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty })
    }

    /// Allowed, refused (macOS will not ask again) or not decided, per app, from the current cache.
    static var accessByTarget: [String: AutomationAllowPlan.Access] {
        var access: [String: AutomationAllowPlan.Access] = [:]
        for id in players {
            switch cachedStatus(id) {
            case .granted: access[id] = .allowed
            case .denied(let code) where code == OSStatus(errAEEventNotPermitted): access[id] = .refused
            case .denied, .pending: access[id] = .undecided
            }
        }
        return access
    }

    /// Asks only `ids` (running apps not yet allowed) without holding the caller: the consent sheet can stay
    /// up until the person answers. Returns, per app, whether it is now allowed.
    static func askAsync(only ids: [String]) async -> [String: Bool] {
        let running = ids.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
        guard !running.isEmpty else { return [:] }
        for id in running { promptBegan(id) }
        let codes = await Task.detached(priority: .userInitiated) { () -> [String: OSStatus] in
            var codes: [String: OSStatus] = [:]
            for id in running { codes[id] = promptStatus(id) }
            return codes
        }.value
        for (id, code) in codes { promptAnswered(id, code) }
        return codes.mapValues { $0 == noErr }
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

    /// One model per target app, all under `cacheLock`. Every change goes through `apply`.
    nonisolated(unsafe) private static var states: [String: AutomationConsentCache.State] = [:]
    private static let cacheLock = NSLock()
    /// Status checks are bounded: macOS can block AEDeterminePermission... when a consent sheet is up.
    static let checkTimeout: TimeInterval = 1.0

    private static var now: Double { Date().timeIntervalSinceReferenceDate }

    /// Runs one event through the consent model for `bundleID` and returns its effects (performed by the caller).
    private static func apply(_ bundleID: String, _ event: AutomationConsentCache.Event) -> [AutomationConsentCache.Effect] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let (next, effects) = AutomationConsentCache.reduce(states[bundleID] ?? AutomationConsentCache.State(), event)
        states[bundleID] = next
        return effects
    }

    private static func cachedStatus(_ bundleID: String) -> Cached {
        scheduleCheck(bundleID)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        switch (states[bundleID] ?? AutomationConsentCache.State()).status(now: now) {
        case .granted: return .granted
        case .denied(let code): return .denied(OSStatus(code))
        case .pending: return .pending
        }
    }

    /// The consent sheet is about to be raised: any check already running is now older than the answer.
    private static func promptBegan(_ bundleID: String) {
        _ = apply(bundleID, .promptBegan)
    }

    /// The person answered. This is newer than every check that started before the prompt.
    static func promptAnswered(_ bundleID: String, _ code: OSStatus) {
        perform(apply(bundleID, .promptAnswered(code: Int32(code), now: now)), for: bundleID)
    }

    private static func scheduleCheck(_ bundleID: String) {
        guard case .startCheck(let generation)? = apply(bundleID, .checkWanted(now: now)).first else { return }

        DispatchQueue.global(qos: .utility).async {
            let box = StatusBox()
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                box.value = performStatus(bundleID, ask: false)
                done.signal()
            }
            var answered = done.wait(timeout: .now() + checkTimeout) == .success
            if !answered {
                _ = apply(bundleID, .checkSlow(generation: generation, now: now))
                answered = done.wait(timeout: .now() + 30) == .success
            }
            let effects = apply(bundleID, .checkEnded(generation: generation, code: answered ? Int32(box.value) : nil, now: now))
            perform(effects, for: bundleID)
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
        waitForChecksToEndForTesting()
        cacheLock.lock()
        states.removeAll()
        cacheLock.unlock()
        testStatusProvider = nil
        for id in players { UserDefaults.standard.removeObject(forKey: grantKey(id)) }
    }

    /// Test hook: blocks until no background check is running (bounded).
    static func waitForChecksToEndForTesting(seconds: TimeInterval = 4) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            cacheLock.lock()
            let busy = states.values.contains { $0.checking }
            cacheLock.unlock()
            if !busy { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// Test hook: the persisted grant for a target.
    static func grantIsRemembered(_ bundleID: String) -> Bool { UserDefaults.standard.bool(forKey: grantKey(bundleID)) }
}

/// Global key and mouse-posting features wait for Accessibility instead of triggering a macOS
/// prompt mid-use. Untrusted, the work is retried every 3 s (a cheap check) until it is granted
/// from setup or Settings > Permissions.
@MainActor
enum AccessibilityGate {
    /// The closure for each waiting feature, by key (see `TrustWait`).
    private static var work: [String: () -> Void] = [:]
    private static var wait = TrustWait.State()
    private static var timer: Timer?

    static var trusted: Bool { AXIsProcessTrusted() }

    /// Runs `work` once Accessibility is on. Asking again under the same key replaces the earlier closure,
    /// so a feature that restarts is started once. The default key names the call site.
    static func whenTrusted(key: String = "\(#fileID):\(#line)", _ work: @escaping () -> Void) {
        self.work[key] = work
        perform(apply(.wanted(key: key, trusted: trusted)))
    }

    /// The feature behind `key` was turned off: it must not start later, and the poll stops with the last waiter.
    static func cancelWaiting(key: String) {
        work[key] = nil
        perform(apply(.cancelled(key: key)))
    }

    private static func apply(_ event: TrustWait.Event) -> [TrustWait.Effect] {
        let (next, effects) = TrustWait.reduce(wait, event)
        wait = next
        return effects
    }

    private static func perform(_ effects: [TrustWait.Effect]) {
        for effect in effects {
            switch effect {
            case .run(let key):
                work.removeValue(forKey: key)?()
            case .startPolling:
                timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                    MainActor.assumeIsolated {
                        guard trusted else { return }
                        NSLog("[ZEUS] permissions: Accessibility granted, starting %d key features", wait.waiting.count)
                        perform(apply(.becameTrusted))
                    }
                }
            case .stopPolling:
                timer?.invalidate()
                timer = nil
            }
        }
    }
}
