import AppKit
import CoreLocation
import Network
import Observation
import ZeusCore

/// The Insomnia tab and its Settings: a keep-awake session (KeepAwakeSession: countdown, battery
/// and heat rules) plus, when Tony turns it on, lid-closed mode (LidSleepGuard: disablesleep through
/// the admin rule, screen off, frozen apps, mute, Low Power, hotspot handoff, tmux nudges).
/// Ending a session, by hand, by time or by a battery or heat rule, always restores everything.
@MainActor
@Observable
final class InsomniaController {
    static let shared = InsomniaController()

    enum EntryMode: String, CaseIterable, Identifiable {
        case length = "For", until = "Until"
        var id: String { rawValue }
    }

    // MARK: Settings (UserDefaults; the hotspot password lives in the Keychain only)

    var lidClosedMode: Bool { didSet { save(lidClosedMode, "insomnia.lidClosed"); lidModeChanged() } }
    var freezeBundleIDs: [String] { didSet { save(freezeBundleIDs, "insomnia.freeze") } }
    var hotspotSSID: String { didSet { save(hotspotSSID, "insomnia.hotspotSSID") } }
    var nudgeAgents: Bool { didSet { save(nudgeAgents, "insomnia.nudge") } }
    var nudgeMinutes: Int { didSet { save(nudgeMinutes, "insomnia.nudgeMinutes") } }
    var muteOnClose: Bool { didSet { save(muteOnClose, "insomnia.mute") } }
    var lowPowerOnBattery: Bool { didSet { save(lowPowerOnBattery, "insomnia.lowPower") } }

    static let nudgeChoices = [5, 10, 15, 20, 30]
    static let hotspotAccount = "insomnia.hotspotPassword"

    // MARK: Time entry

    var duration = InsomniaDuration(hours: 1, minutes: 0)
    var entryMode: EntryMode = .length
    var untilText = "23:30"

    // MARK: State

    private(set) var setup: InsomniaInstaller.Status = .notInstalled
    private(set) var setupBusy = false
    private(set) var setupMessage: String?
    private(set) var lidArmed = false
    /// Why the last arm attempt failed (nil when it has not, or after one worked): the Lid row says so.
    private(set) var armFailure: String?
    private(set) var lidClosed: Bool?
    private(set) var frozenCount = 0
    private(set) var hotspotStatus = "Not needed"
    private(set) var lastNudge = "None yet"
    private(set) var message: String?
    private(set) var online = true
    private(set) var hasHotspotPassword = false

    @ObservationIgnored private let guardian: LidSleepGuard
    @ObservationIgnored private let installer: InsomniaInstaller
    @ObservationIgnored private let queue = DispatchQueue(label: "app.zeus.insomnia", qos: .userInitiated)
    @ObservationIgnored private let lid = LidMonitor()
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var nudgeTimer: Timer?
    @ObservationIgnored private var restoreRetry: Timer?
    @ObservationIgnored private var lastHotspotTry = Date.distantPast
    @ObservationIgnored private var observing = false

    init(guardian: LidSleepGuard = LidSleepGuard(), installer: InsomniaInstaller = InsomniaInstaller()) {
        self.guardian = guardian
        self.installer = installer
        let defaults = UserDefaults.standard
        lidClosedMode = defaults.object(forKey: "insomnia.lidClosed") as? Bool ?? true
        freezeBundleIDs = defaults.stringArray(forKey: "insomnia.freeze") ?? []
        hotspotSSID = defaults.string(forKey: "insomnia.hotspotSSID") ?? ""
        nudgeAgents = defaults.object(forKey: "insomnia.nudge") as? Bool ?? false
        nudgeMinutes = defaults.object(forKey: "insomnia.nudgeMinutes") as? Int ?? 10
        muteOnClose = defaults.object(forKey: "insomnia.mute") as? Bool ?? true
        lowPowerOnBattery = defaults.object(forKey: "insomnia.lowPower") as? Bool ?? true
        if let minutes = defaults.object(forKey: "insomnia.minutes") as? Int {
            duration = minutes > 0 ? InsomniaDuration(hours: 0, minutes: minutes) : InsomniaDuration(indefinite: true)
        }
        lid.onChange = { [weak self] closed in self?.lidChanged(closed) }
    }

    var session: KeepAwakeSession { .shared }
    var isRunning: Bool { session.isActive }

    // MARK: Launch and quit

    /// Called once at launch: undo a session a crash left behind, then read the setup status.
    func launch() {
        guard !observing else { return }
        observing = true
        session.observeEnd { [weak self] in self?.sessionEnded() }
        hasHotspotPassword = Keychain.get(Self.hotspotAccount) != nil
        work({ $0.recoverLeftover() }) { [weak self] report in
            // nil means nothing was left over. A failed report may have nothing in `done`: still report and retry.
            guard let report else { return }
            if report.ok {
                if !report.done.isEmpty { self?.message = "Restored a lid-closed session Zeus could not end last time." }
            } else {
                self?.message = "Restored a leftover session with problems: " + report.failed.joined(separator: "; ")
                self?.scheduleRestoreRetry()
            }
        }
        refreshSetup()
    }

    /// Zeus is quitting: put everything back before the process goes.
    func shutdown() {
        stopWatching()
        lidArmed = false
        restoreRetry?.invalidate()
        restoreRetry = nil
        // The queue is held by the macOS admin prompt (up to 300 s): never wait on it. The journal stays,
        // so the next launch (or the backstop agent) restores what is left.
        guard !setupBusy else { return }
        let guardian = guardian
        let done = DispatchSemaphore(value: 0)
        queue.async {
            if guardian.isArmed { _ = guardian.disarm() }
            done.signal()
        }
        // Bounded: lid work in flight is short, and a stuck restore must not hang quit.
        _ = done.wait(timeout: .now() + 3)
    }

    // MARK: Session

    /// Minutes from the entry (nil is Indefinitely); nil too for an Until time that does not parse.
    var enteredMinutes: Int?? {
        switch entryMode {
        case .length: return .some(duration.totalMinutes)
        case .until:
            guard let clock = InsomniaDuration.parseClock(untilText) else { return nil }
            return .some(InsomniaDuration.minutes(until: clock.hour, clock.minute, from: Date()))
        }
    }

    func start() {
        guard let minutes = enteredMinutes else {
            message = "Type a time like 23:30."
            return
        }
        message = nil
        armFailure = nil
        save(minutes ?? 0, "insomnia.minutes")
        session.start(minutes: minutes)
        if lidClosedMode { armLid() }
    }

    func stop() { session.end() }

    func add(minutes: Int) {
        session.add(minutes: minutes)
        syncPlannedEnd()
    }

    func applyChip(_ minutes: Int?) {
        entryMode = .length
        duration.apply(chip: minutes)
    }

    private func lidModeChanged() {
        guard isRunning else { return }
        if lidClosedMode { armLid() } else { disarmLid() }
    }

    private func armLid() {
        guard !lidArmed else { syncPlannedEnd(); return }
        guard setup.isReady else {
            message = "Keeping the Mac awake. For lid-closed mode, set it up once below."
            return
        }
        let end = session.endsAt
        work({ $0.arm(plannedEnd: end) }) { [weak self] report in
            guard let self else { return }
            guard report.ok else {
                self.message = report.message
                // The Lid row must not keep saying "Armed when you start" after the arm failed.
                self.armFailure = report.message
                self.refreshSetup()
                return
            }
            self.armFailure = nil
            // The session may have ended while the admin call ran.
            guard self.isRunning else { self.disarmLid(); return }
            self.lidArmed = true
            self.message = nil
            self.startWatching()
        }
    }

    private func disarmLid() {
        stopWatching()
        lidArmed = false
        work({ $0.disarm() }) { [weak self] report in
            guard let self else { return }
            self.frozenCount = 0
            if !report.ok {
                self.message = "Restored with problems: " + report.failed.joined(separator: "; ")
                self.scheduleRestoreRetry()
            }
        }
    }

    /// A restore that failed keeps its journal; try again every minute while no session is running.
    private func scheduleRestoreRetry(attempt: Int = 1) {
        restoreRetry?.invalidate()
        guard attempt <= 30 else { return }
        let timer = Timer(timeInterval: 60, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.retryRestore(attempt: attempt) }
        }
        RunLoop.main.add(timer, forMode: .common)
        restoreRetry = timer
    }

    private func retryRestore(attempt: Int) {
        restoreRetry = nil
        // A new session owns the journal now; its own end restores everything.
        guard !isRunning, !lidArmed, !setupBusy else { return }
        // After a failed disarm the guard still holds the journal, so retry through disarm; recoverLeftover skips it.
        work({ guardian -> InsomniaRestorer.Report? in guardian.isArmed ? guardian.disarm() : guardian.recoverLeftover() }) { [weak self] report in
            guard let self, let report else { return }
            if report.ok {
                if !report.done.isEmpty { self.message = "Restored the Mac's sleep settings." }
            } else {
                self.message = "Restored with problems, retrying: " + report.failed.joined(separator: "; ")
                self.scheduleRestoreRetry(attempt: attempt + 1)
            }
        }
    }

    private func sessionEnded() {
        if lidArmed { disarmLid() }
    }

    private func syncPlannedEnd() {
        guard lidArmed else { return }
        let end = session.endsAt
        work({ $0.setPlannedEnd(end) }) { _ in }
    }

    // MARK: Lid, network, nudges

    private func startWatching() {
        lid.start()
        lidClosed = lid.isClosed
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(up) }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
        nudgeTimer?.invalidate()
        let timer = Timer(timeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.everyTwoMinutes() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        nudgeTimer = timer
        if lid.isClosed == true { lidChanged(true) }
    }

    private func stopWatching() {
        lid.stop()
        pathMonitor?.cancel()
        pathMonitor = nil
        nudgeTimer?.invalidate()
        nudgeTimer = nil
        lidClosed = nil
    }

    private func lidChanged(_ closed: Bool) {
        lidClosed = closed
        guard lidArmed else { return }
        if closed {
            let options = currentOptions
            let running = Self.runningProcesses()
            let onBattery = PowerMonitor.shared.power.onBattery
            work({ ($0.lidClosed(options: options, running: running, onBattery: onBattery), $0.frozenCount) }) { [weak self] result in
                guard let self else { return }
                let (report, frozen) = result
                self.frozenCount = frozen
                if !report.notes.isEmpty { self.message = report.notes.joined(separator: " ") }
                self.tryHotspotIfOffline()
            }
        } else {
            work({ $0.lidOpened() }) { [weak self] report in
                guard let self else { return }
                self.frozenCount = 0
                if !report.ok { self.message = "Lid open, with problems: " + report.failed.joined(separator: "; ") }
            }
        }
    }

    private func networkChanged(_ up: Bool) {
        online = up
        if up, hotspotStatus.hasPrefix("Trying") { hotspotStatus = "Online" }
        tryHotspotIfOffline()
    }

    private func tryHotspotIfOffline() {
        guard lidArmed, lidClosed == true, !online, !hotspotSSID.isEmpty,
              Date().timeIntervalSince(lastHotspotTry) > 110 else { return }
        lastHotspotTry = Date()
        hotspotStatus = "Trying \(hotspotSSID)…"
        let ssid = hotspotSSID
        let password = Keychain.get(Self.hotspotAccount)
        let status = CLLocationManager().authorizationStatus
        let location = status == .authorizedAlways || status == .authorized
        work({ $0.joinHotspot(ssid: ssid, password: password, locationAllowed: location) }) { [weak self] text in
            self?.hotspotStatus = text
        }
    }

    private func everyTwoMinutes() {
        syncPlannedEnd()
        tryHotspotIfOffline()
        guard nudgeAgents else { return }
        let minutes = nudgeMinutes
        work({ $0.nudgeRound(minutes: minutes) }) { [weak self] report in
            guard let self else { return }
            if report.tmuxMissing {
                self.lastNudge = "tmux not found, nudges off"
            } else if !report.nudged.isEmpty {
                self.lastNudge = "\(report.nudged.joined(separator: ", ")) at \(Date().formatted(date: .omitted, time: .shortened))"
            }
        }
    }

    private var currentOptions: LidSleepGuard.Options {
        LidSleepGuard.Options(freezeBundleIDs: freezeBundleIDs, mute: muteOnClose, lowPower: lowPowerOnBattery,
                              hotspotSSID: hotspotSSID, nudge: nudgeAgents, nudgeMinutes: nudgeMinutes)
    }

    // MARK: Setup

    func refreshSetup() {
        let installer = installer
        queue.async {
            let status = installer.status()
            Task { @MainActor [weak self] in self?.setup = status }
        }
    }

    /// One click: the macOS admin prompt appears; Zeus never sees the password.
    func installRule() {
        runSetup { $0.install() }
    }

    func uninstallRule() {
        if isRunning, lidArmed { disarmLid() }
        runSetup { $0.uninstall() }
    }

    private func runSetup(_ job: @escaping @Sendable (InsomniaInstaller) -> InsomniaInstaller.Outcome) {
        guard !setupBusy else { return }
        setupBusy = true
        setupMessage = "Waiting for the macOS admin prompt…"
        let installer = installer
        queue.async {
            let outcome = job(installer)
            let status = installer.status()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.setupBusy = false
                self.setup = status
                self.setupMessage = outcome.text
                if status.isReady, self.isRunning, self.lidClosedMode { self.armLid() }
            }
        }
    }

    // MARK: Hotspot password (Keychain only)

    /// False when the Keychain refused: the saved state is unchanged, `setupMessage` says so and the caller keeps the draft.
    @discardableResult
    func saveHotspotPassword(_ password: String) -> Bool {
        if password.isEmpty {
            guard Keychain.remove(Self.hotspotAccount) else {
                setupMessage = "Couldn't remove the hotspot password. Check Keychain access and try again."
                return false
            }
        } else if !Keychain.set(password, for: Self.hotspotAccount) {
            setupMessage = "Couldn't save the hotspot password to your Keychain. It is still in the field."
            return false
        }
        hasHotspotPassword = !password.isEmpty
        return true
    }

    // MARK: Status lines

    var lidText: String {
        guard lidArmed else {
            guard lidClosedMode else { return "Off" }
            if let armFailure { return "Not armed: \(armFailure)" }
            if isRunning { return setup.isReady ? "Arming…" : "Not armed: needs setup" }
            return setup.isReady ? "Armed when you start" : "Needs setup"
        }
        switch lidClosed {
        case true?: return "Closed, still working"
        case false?: return "Open"
        case nil: return "No lid on this Mac"
        }
    }

    var batteryText: String {
        let power = PowerMonitor.shared.power
        guard let percent = power.batteryPercent else { return "On power" }
        return "\(percent)%" + (power.isCharging ? ", charging" : power.onBattery ? ", on battery" : ", plugged in")
    }

    var heatText: String {
        switch PowerMonitor.shared.power.thermal {
        case .nominal: "Cool"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Too hot"
        }
    }

    var endText: String {
        guard let reason = session.lastEnd else { return isRunning ? "Running" : "None" }
        return reason.text
    }

    // MARK: Freeze list

    struct AppChoice: Identifiable, Equatable {
        var id: String { bundleID }
        var bundleID: String
        var name: String
    }

    /// Running apps Tony can add to the freeze list: regular apps, not protected.
    func freezableRunningApps() -> [AppChoice] {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var seen = Set<String>()
        return apps.compactMap { app -> AppChoice? in
            guard let id = app.bundleIdentifier, !InsomniaFreezePolicy.isProtected(bundleID: id), seen.insert(id).inserted else { return nil }
            return AppChoice(bundleID: id, name: app.localizedName ?? id)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func toggleFreeze(_ bundleID: String) {
        if let index = freezeBundleIDs.firstIndex(of: bundleID) { freezeBundleIDs.remove(at: index) } else { freezeBundleIDs.append(bundleID) }
    }

    static func runningProcesses() -> [InsomniaFreezePolicy.RunningProcess] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier else { return nil }
            return .init(pid: app.processIdentifier, bundleID: id, name: app.executableURL?.lastPathComponent ?? "")
        }
    }

    // MARK: Helpers

    private func work<T: Sendable>(_ job: @escaping @Sendable (LidSleepGuard) -> T,
                                   then: @escaping @MainActor @Sendable (T) -> Void) {
        let guardian = guardian
        queue.async {
            let result = job(guardian)
            Task { @MainActor in then(result) }
        }
    }

    private func save(_ value: Any, _ key: String) {
        if !TopBarStyle.isSnapshot { UserDefaults.standard.set(value, forKey: key) }
    }
}
