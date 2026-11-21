import Foundation

@main
struct BudgetMain {
    static func main() {
        var failed = false
        func expect(_ ok: Bool, _ message: String) {
            if ok { return }
            failed = true
            fputs("FAIL \(message)\n", stderr)
        }

        var clock = HubManualClock()
        let slow = HubExperience.measureOpen(clock: &clock) { clock in
            clock.advance(milliseconds: 101)
        }
        expect(slow.elapsedMilliseconds == 101, "elapsed \(slow.elapsedMilliseconds)")
        expect(slow.meetsBudget == false, "101 ms was accepted")

        var exact = HubManualClock()
        let onBudget = HubExperience.measureOpen(clock: &exact) { clock in
            clock.advance(milliseconds: 100)
        }
        expect(onBudget.meetsBudget, "100 ms was rejected")

        var idleClock = HubManualClock()
        let quiet = HubIdleSample(
            panelClosed: true, approvalShowing: false, socketReadInProgress: false,
            oneSecondTimerScheduled: false, waveDisplayLinkRunning: false, percentOfOneCore: 1)
        let held = HubExperience.measureIdle(clock: &idleClock, windowMilliseconds: 60_000, sample: quiet)
        expect(held.elapsedMilliseconds == 60_000, "window \(held.elapsedMilliseconds)")
        expect(held.meetsBudget, "1% over 60 s was rejected")

        var hotClock = HubManualClock()
        var hot = quiet
        hot.percentOfOneCore = 1.1
        let over = HubExperience.measureIdle(clock: &hotClock, windowMilliseconds: 60_000, sample: hot)
        expect(over.meetsBudget == false, "1.1% was accepted")

        var ticking = quiet
        ticking.oneSecondTimerScheduled = true
        let timer = HubExperience.measureIdle(clock: &hotClock, windowMilliseconds: 60_000, sample: ticking)
        expect(timer.meetsBudget == false, "a closed-panel timer was idle")

        if failed { exit(1) }
        fputs("hub budget ok\n", stderr)
    }
}
