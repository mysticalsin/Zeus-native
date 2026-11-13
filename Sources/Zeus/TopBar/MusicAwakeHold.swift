import Foundation
import IOKit.pwr_mgt
import ZeusCore

/// Holds the display on while music plays, if the person asked for it (Settings > General).
/// It owns one display-sleep assertion with a two-minute lease, renewed each minute, so a hung
/// Zeus cannot keep the screen on. `MusicAwakeRule` decides; this class only carries it out.
/// It is separate from `KeepAwakeSession` and the Home cup and never touches either. It reads
/// the session's battery floor and heat setting so the same limits apply.
@MainActor
final class MusicAwakeHold {
    static let shared = MusicAwakeHold()
    /// The catalog id of the setting.
    static let settingID = "keepAwake.whileMusic"
    /// How long one assertion lasts if Zeus stops renewing it.
    static let lease: TimeInterval = 120
    private static let renewEvery: TimeInterval = 60

    /// True while the assertion is held.
    var isHolding: Bool { assertion != nil }

    private let rule = MusicAwakeRule()
    private let monitor: PowerMonitor?
    private let clock: () -> Date
    private let readPower: () -> KeepAwakeRules.Power
    private let readRules: () -> KeepAwakeRules
    private let create: (TimeInterval) -> IOPMAssertionID?
    private let release: (IOPMAssertionID) -> Void
    private let schedule: Schedule

    private var enabled = false
    private var playing = false
    private var lastPlayedAt: Date?
    private var assertion: IOPMAssertionID?
    private var watching = false
    private var cancelRenew: (() -> Void)?
    private var cancelGrace: (() -> Void)?

    /// Runs a callback on the main actor after a delay, once or repeating. Returns a closure that cancels it.
    typealias Schedule = (TimeInterval, _ repeats: Bool, @escaping @MainActor () -> Void) -> () -> Void

    /// The defaults are the real clock, the shared power monitor, the keep-awake rules and real timers.
    /// Tests answer for power, rules, the assertion and the timers themselves.
    init(monitor: PowerMonitor? = PowerMonitor.shared,
         clock: @escaping () -> Date = Date.init,
         power: (() -> KeepAwakeRules.Power)? = nil,
         rules: @escaping () -> KeepAwakeRules = { KeepAwakeSession.shared.rules },
         create: @escaping (TimeInterval) -> IOPMAssertionID? = MusicAwakeHold.createAssertion,
         release: @escaping (IOPMAssertionID) -> Void = { IOPMAssertionRelease($0) },
         schedule: @escaping Schedule = MusicAwakeHold.timerSchedule) {
        self.monitor = monitor
        self.clock = clock
        self.readPower = power ?? { monitor?.power ?? KeepAwakeRules.Power() }
        self.readRules = rules
        self.create = create
        self.release = release
        self.schedule = schedule
    }

    /// The setting changed. Takes effect at once.
    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        evaluate()
    }

    /// A track started or stopped playing. Tracked even while the setting is off, so turning it on
    /// during a song holds right away.
    func setPlaying(_ on: Bool) {
        guard on != playing else { return }
        playing = on
        lastPlayedAt = clock()
        evaluate()
    }

    /// Runs the rule against the current state: on every change, on a power or heat change, when the
    /// grace ends and once a minute (which also renews the lease).
    func evaluate(renewLease: Bool = false) {
        let now = clock()
        let rules = readRules()
        // Power is only worth watching while a hold could be wanted. Ask once with calm power, so a low
        // battery still keeps watching and the hold comes back when power or heat recovers.
        let wanted = rule.decide(enabled: enabled, isPlaying: playing, lastPlayedAt: lastPlayedAt, now: now,
                                 power: KeepAwakeRules.Power(), rules: rules).holds
        setWatching(wanted)
        let verdict = rule.decide(enabled: enabled, isPlaying: playing, lastPlayedAt: lastPlayedAt, now: now,
                                  power: readPower(), rules: rules)
        if verdict.holds {
            if assertion == nil || renewLease { renew() }
            startRenewTimer()
        } else {
            drop()
        }
        scheduleGraceEnd(now: now)
    }

    // MARK: Assertion

    /// Takes a fresh assertion before letting go of the old one, so the display never gets a gap.
    private func renew() {
        guard let fresh = create(Self.lease) else { return }
        if let old = assertion { release(old) }
        assertion = fresh
    }

    private func drop() {
        cancelRenew?()
        cancelRenew = nil
        if let old = assertion { release(old) }
        assertion = nil
    }

    nonisolated static func createAssertion(timeout: TimeInterval) -> IOPMAssertionID? {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithDescription(
            "PreventUserIdleDisplaySleep" as CFString,
            "Zeus music display hold" as CFString,
            "Holds the display on while music plays. Ends when the music stops, a battery or heat rule trips, or you turn it off." as CFString,
            nil, nil,
            timeout,
            "TimeoutActionRelease" as CFString,
            &id)
        return result == kIOReturnSuccess ? id : nil
    }

    // MARK: Timers and power

    /// Real timers, with some slack so the system can batch the wake-ups. The lease is 120 seconds and
    /// renewal runs every 60, so ten seconds late is still safe; the grace end may be half a second late.
    nonisolated static func timerSchedule(after delay: TimeInterval, repeats: Bool,
                                          fire: @escaping @MainActor () -> Void) -> () -> Void {
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: repeats) { _ in
            MainActor.assumeIsolated { fire() }
        }
        timer.tolerance = repeats ? 10 : 0.5
        return { timer.invalidate() }
    }

    private func startRenewTimer() {
        guard cancelRenew == nil else { return }
        cancelRenew = schedule(Self.renewEvery, true) { [weak self] in self?.evaluate(renewLease: true) }
    }

    /// One shot for the moment the grace runs out, so a pause that never resumes lets go on time.
    private func scheduleGraceEnd(now: Date) {
        cancelGrace?()
        cancelGrace = nil
        guard enabled, !playing, let lastPlayedAt else { return }
        let left = rule.grace - now.timeIntervalSince(lastPlayedAt)
        guard left > 0, left <= rule.grace else { return }
        // A hair past the end, so the rule sees the grace as over.
        cancelGrace = schedule(left + 0.05, false) { [weak self] in self?.evaluate() }
    }

    /// Lets go of everything: both timers, the assertion and the power watch. For teardown and tests;
    /// the next change starts it all again.
    func invalidate() {
        drop()
        cancelGrace?()
        cancelGrace = nil
        setWatching(false)
    }

    /// Joins the shared power monitor only while a hold could be wanted. The keep-awake session keeps
    /// its own callback; this one uses the second slot.
    private func setWatching(_ on: Bool) {
        guard on != watching, let monitor else { return }
        watching = on
        if on {
            monitor.onMusicChange = { [weak self] in self?.evaluate() }
            monitor.start(for: .music)
        } else {
            monitor.stop(for: .music)
            monitor.onMusicChange = {}
        }
    }
}
