import Foundation
import IOKit.pwr_mgt
import Observation
import ZeusCore

/// Timed keep-awake session (Stage B): countdown, add time, end early.
/// Uses PreventUserIdleSystemSleep with a timeout so a hung Zeus never holds the Mac forever.
/// Display-sleep option is separate (Home cup). Restores by releasing the assertion — no sudoers.
/// `KeepAwakeRules` can end it early on low battery or heat; the reason stays in `lastEnd`.
@MainActor @Observable
final class KeepAwakeSession {
    static let shared = KeepAwakeSession()

    /// Preset minutes offered in Settings / Home.
    static let presets = KeepAwakeLength.short
    /// Longer presets; Settings and Home also offer Indefinitely (nil minutes).
    static let longPresets = KeepAwakeLength.long
    /// Assertion lease for an open-ended session, renewed every minute.
    private static let openEndedLease: TimeInterval = 5 * 60

    private(set) var endsAt: Date?
    private(set) var isActive = false
    /// True for an Indefinitely session: no countdown, ends only by hand or by a rule.
    private(set) var isOpenEnded = false
    private(set) var remaining: TimeInterval = 0
    /// Why the last session stopped by itself. Cleared when a new one starts or you end one.
    private(set) var lastEnd: KeepAwakeRules.EndReason?
    /// When true, also keep the display awake for the session.
    var keepDisplay = UserDefaults.standard.bool(forKey: "keepAwake.display") {
        didSet { if !TopBarStyle.isSnapshot { UserDefaults.standard.set(keepDisplay, forKey: "keepAwake.display") }; reassert() }
    }
    /// End below this battery percent on battery power. 0 is Off.
    var batteryFloor = UserDefaults.standard.object(forKey: "keepAwake.batteryFloor") as? Int ?? 10 {
        didSet { save(batteryFloor, "keepAwake.batteryFloor"); evaluate() }
    }
    /// End when the Mac reaches a critical thermal state.
    var endWhenHot = UserDefaults.standard.object(forKey: "keepAwake.endWhenHot") as? Bool ?? true {
        didSet { save(endWhenHot, "keepAwake.endWhenHot"); evaluate() }
    }
    /// Length the Home cup starts. Nil is Indefinitely (saved as 0).
    var homeMinutes: Int? = KeepAwakeSession.storedHomeMinutes() {
        didSet { save(homeMinutes ?? 0, "keepAwake.homeMinutes") }
    }

    /// One-line notices for the notch (low-battery warning, rule end).
    @ObservationIgnored var onNotice: (String) -> Void = { _ in }
    /// Called whenever a session ends, by hand or by a rule.
    @ObservationIgnored var onEnd: () -> Void = {}
    /// More listeners for the end (the Insomnia lid-closed guard restores on it).
    @ObservationIgnored private var endObservers: [() -> Void] = []

    func observeEnd(_ observer: @escaping () -> Void) { endObservers.append(observer) }

    @ObservationIgnored private var systemID: IOPMAssertionID = 0
    @ObservationIgnored private var displayID: IOPMAssertionID = 0
    @ObservationIgnored private var hasSystem = false
    @ObservationIgnored private var hasDisplay = false
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var lastCheck = Date.distantPast
    @ObservationIgnored private var warned = false

    var rules: KeepAwakeRules { KeepAwakeRules(batteryFloor: batteryFloor, endWhenHot: endWhenHot) }

    var label: String {
        guard isActive else { return "Off" }
        return KeepAwakeLength.countdown(isOpenEnded ? nil : remaining)
    }

    /// Nil minutes keeps the Mac awake until you end it or a rule does.
    func start(minutes: Int?) {
        isOpenEnded = minutes == nil
        endsAt = minutes.map { Date().addingTimeInterval(TimeInterval(max(1, $0) * 60)) }
        remaining = endsAt?.timeIntervalSinceNow ?? 0
        isActive = true
        startedAt = Date()
        lastEnd = nil
        warned = false
        reassert()
        ticker?.invalidate()
        // The countdown needs a second hand; an open-ended session only renews its lease.
        ticker = Timer.scheduledTimer(withTimeInterval: isOpenEnded ? 60 : 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        PowerMonitor.shared.onChange = { [weak self] in self?.evaluate() }
        PowerMonitor.shared.start()
        evaluate()
    }

    func add(minutes: Int) {
        guard isActive else { start(minutes: minutes); return }
        guard !isOpenEnded else { return }
        endsAt = (endsAt ?? Date()).addingTimeInterval(TimeInterval(minutes * 60))
        tick()
        reassert()
    }

    /// Ends by hand: no reason is kept.
    func end() {
        stop()
        lastEnd = nil
    }

    private func stop() {
        ticker?.invalidate()
        ticker = nil
        endsAt = nil
        remaining = 0
        isActive = false
        isOpenEnded = false
        releaseAll()
        PowerMonitor.shared.stop()
        onEnd()
        endObservers.forEach { $0() }
    }

    private func tick() {
        guard isActive else { return }
        if isOpenEnded {
            reassert()
        } else if let endsAt {
            remaining = max(0, endsAt.timeIntervalSinceNow)
        }
        if (!isOpenEnded && remaining <= 0) || Date().timeIntervalSince(lastCheck) >= 60 { evaluate() }
    }

    /// Runs the rules on power and thermal changes, on settings changes and once a minute.
    private func evaluate() {
        guard isActive else { return }
        lastCheck = Date()
        let verdict = rules.evaluate(PowerMonitor.shared.power,
                                     elapsed: Date().timeIntervalSince(startedAt),
                                     remaining: isOpenEnded ? nil : remaining,
                                     warned: warned)
        switch verdict {
        case .keepGoing:
            break
        case .warnLowBattery(let percent):
            warned = true
            onNotice(batteryFloor > 0 ? "Battery \(percent)%. Ends below \(batteryFloor)%." : "Battery \(percent)%. Still awake.")
        case .end(let reason):
            stop()
            lastEnd = reason
            if reason != .timeUp { onNotice(reason.text) }
        }
    }

    private func reassert() {
        releaseAll()
        guard isActive else { return }
        let timeout = endsAt.map { max(30, $0.timeIntervalSinceNow + 5) } ?? Self.openEndedLease
        if create("PreventUserIdleSystemSleep", reason: "Zeus keep-awake session", timeout: timeout, into: &systemID) {
            hasSystem = true
        }
        if keepDisplay,
           create("PreventUserIdleDisplaySleep", reason: "Zeus keep-awake display", timeout: timeout, into: &displayID) {
            hasDisplay = true
        }
    }

    private func releaseAll() {
        if hasSystem { IOPMAssertionRelease(systemID); hasSystem = false }
        if hasDisplay { IOPMAssertionRelease(displayID); hasDisplay = false }
    }

    private func save(_ value: Any, _ key: String) {
        if !TopBarStyle.isSnapshot { UserDefaults.standard.set(value, forKey: key) }
    }

    private static func storedHomeMinutes() -> Int? {
        guard let minutes = UserDefaults.standard.object(forKey: "keepAwake.homeMinutes") as? Int else { return 30 }
        return minutes > 0 ? minutes : nil
    }

    private func create(_ type: String, reason: String, timeout: Double, into id: inout IOPMAssertionID) -> Bool {
        var local = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithDescription(
            type as CFString,
            reason as CFString,
            "Session from Zeus. Ends when the countdown hits zero, a battery or heat rule trips, or you end it." as CFString,
            nil, nil,
            timeout,
            "TimeoutActionRelease" as CFString,
            &local)
        if result == kIOReturnSuccess {
            id = local
            return true
        }
        return false
    }
}
