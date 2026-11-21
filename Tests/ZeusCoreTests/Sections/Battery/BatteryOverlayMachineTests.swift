import Foundation
import Testing
import ZeusCore

@Suite("Battery overlay when power changes")
struct BatteryOverlayMachineTests {
    private let unplugged = BatteryPowerSample(percent: 64, charging: false, onAC: false)
    private let plugged = BatteryPowerSample(percent: 64, charging: true, onAC: true)

    private func reduce(_ state: BatteryOverlayMachine, _ event: BatteryOverlayMachine.Event) -> (BatteryOverlayMachine, [BatteryOverlayMachine.Effect]) {
        BatteryOverlayMachine.reduce(state, event)
    }

    @Test func pluggingInAChargerShowsTheOverlay() {
        var state = BatteryOverlayMachine()
        state = reduce(state, .power(unplugged, at: 10)).0
        let (next, effects) = reduce(state, .power(plugged, at: 11))
        #expect(effects.count == 1)
        guard case .present(let show) = effects.first else {
            Issue.record("charger connect produced \(effects)")
            return
        }
        #expect(show.trigger == .chargerConnected)
        #expect(show.percent == 64)
        #expect(show.charging)
        #expect(show.style == .gauge)
        #expect(show.until == 11 + BatteryOverlayMachine.showDuration)
        #expect(show.accessibilityLabel == "Charging, 64 percent")
        guard case .showing(let phase) = next.phase else {
            Issue.record("phase \(next.phase)")
            return
        }
        #expect(phase == show)
    }

    @Test func unpluggingTheChargerShowsTheOverlay() {
        var state = BatteryOverlayMachine()
        state = reduce(state, .power(plugged, at: 1)).0
        let (_, effects) = reduce(state, .power(unplugged, at: 2))
        guard case .present(let show) = effects.first else {
            Issue.record("charger disconnect produced \(effects)")
            return
        }
        #expect(show.trigger == .chargerDisconnected)
        #expect(show.accessibilityLabel == "On battery, 64 percent")
        #expect(!show.charging)
    }

    @Test func theFirstReadingDoesNotPretendTheChargerChanged() {
        let (state, effects) = reduce(BatteryOverlayMachine(), .power(plugged, at: 0))
        #expect(effects.isEmpty)
        #expect(state.phase == .idle)
        #expect(state.seeded)
    }

    @Test func aLowBatteryOnTheFirstReadingShows() {
        let sample = BatteryPowerSample(percent: 10, charging: false, onAC: false)
        let (state, effects) = reduce(BatteryOverlayMachine(), .power(sample, at: 4))
        guard case .present(let show) = effects.first else {
            Issue.record("low battery produced \(effects)")
            return
        }
        #expect(show.trigger == .lowBattery)
        #expect(show.percent == 10)
        #expect(show.accessibilityLabel == "Battery low, 10 percent")
        #expect(state.lastLowPercent == 10)
    }

    @Test func elevenPercentOnBatteryDoesNotShowLow() {
        let sample = BatteryPowerSample(percent: 11, charging: false, onAC: false)
        let (_, effects) = reduce(BatteryOverlayMachine(), .power(sample, at: 0))
        #expect(effects.isEmpty)
    }

    @Test func theSameLowPercentDoesNotShowTwice() {
        let sample = BatteryPowerSample(percent: 9, charging: false, onAC: false)
        var state = BatteryOverlayMachine()
        state = reduce(state, .power(sample, at: 0)).0
        state = reduce(state, .advance(to: 0 + BatteryOverlayMachine.showDuration)).0
        state = reduce(state, .advance(to: 0 + BatteryOverlayMachine.showDuration + BatteryOverlayMachine.cooldownDuration)).0
        #expect(state.phase == .idle)
        let (_, effects) = reduce(state, .power(sample, at: 30))
        #expect(effects.isEmpty)
    }

    @Test func aLowerPercentShowsAgainAfterTheCooldown() {
        var state = BatteryOverlayMachine()
        state = reduce(state, .power(BatteryPowerSample(percent: 10, charging: false, onAC: false), at: 0)).0
        state = reduce(state, .advance(to: BatteryOverlayMachine.showDuration)).0
        state = reduce(state, .advance(to: BatteryOverlayMachine.showDuration + BatteryOverlayMachine.cooldownDuration)).0
        let (_, effects) = reduce(state, .power(BatteryPowerSample(percent: 8, charging: false, onAC: false), at: 40))
        guard case .present(let show) = effects.first else {
            Issue.record("next low reading produced \(effects)")
            return
        }
        #expect(show.trigger == .lowBattery)
        #expect(show.percent == 8)
    }

    @Test func showThenCooldownThenIdle() {
        var state = BatteryOverlayMachine()
        state = reduce(state, .power(unplugged, at: 0)).0
        let (showing, presented) = reduce(state, .power(plugged, at: 5))
        guard case .showing(let show) = showing.phase else {
            Issue.record("not showing")
            return
        }
        let (still, none) = reduce(showing, .advance(to: show.until - 0.001))
        #expect(none.isEmpty)
        #expect(still.phase == .showing(show))
        let (cooling, dismissed) = reduce(still, .advance(to: show.until))
        #expect(dismissed == [.dismiss])
        #expect(cooling.phase == .cooldown(until: show.until + BatteryOverlayMachine.cooldownDuration))
        let (held, blocked) = reduce(cooling, .advance(to: show.until + BatteryOverlayMachine.cooldownDuration - 0.001))
        #expect(blocked.isEmpty)
        #expect(held.phase == cooling.phase)
        let (idle, done) = reduce(held, .advance(to: show.until + BatteryOverlayMachine.cooldownDuration))
        #expect(done.isEmpty)
        #expect(idle.phase == .idle)
        #expect(presented.count == 1)
    }

    @Test func aPowerChangeDuringCooldownIsNotShownLater() {
        var state = BatteryOverlayMachine()
        state = reduce(state, .power(unplugged, at: 0)).0
        state = reduce(state, .power(plugged, at: 1)).0
        state = reduce(state, .advance(to: 1 + BatteryOverlayMachine.showDuration)).0
        guard case .cooldown = state.phase else {
            Issue.record("expected cooldown, got \(state.phase)")
            return
        }
        let (swallowed, effects) = reduce(state, .power(unplugged, at: 1 + BatteryOverlayMachine.showDuration + 1))
        #expect(effects.isEmpty)
        #expect(swallowed.phase == state.phase)
        let (idle, _) = reduce(swallowed, .advance(to: 1 + BatteryOverlayMachine.showDuration + BatteryOverlayMachine.cooldownDuration))
        let (_, later) = reduce(idle, .power(unplugged, at: 30))
        #expect(later.isEmpty)
        #expect(idle.phase == .idle)
    }

    @Test func aDifferentTriggerDuringTheShowReplacesIt() {
        var state = BatteryOverlayMachine()
        state = reduce(state, .power(unplugged, at: 0)).0
        state = reduce(state, .power(plugged, at: 2)).0
        let (next, effects) = reduce(state, .power(unplugged, at: 3))
        guard case .present(let show) = effects.first else {
            Issue.record("replacement produced \(effects)")
            return
        }
        #expect(show.trigger == .chargerDisconnected)
        #expect(show.until == 3 + BatteryOverlayMachine.showDuration)
        guard case .showing(let current) = next.phase else {
            Issue.record("phase \(next.phase)")
            return
        }
        #expect(current.trigger == .chargerDisconnected)
    }

    @Test func theSameTriggerDuringTheShowDoesNotRestartTheClock() {
        var state = BatteryOverlayMachine()
        state = reduce(state, .power(unplugged, at: 0)).0
        let (showing, first) = reduce(state, .power(BatteryPowerSample(percent: 40, charging: true, onAC: true), at: 2))
        guard case .present(let original) = first.first else {
            Issue.record("missing present")
            return
        }
        let updated = BatteryPowerSample(percent: 41, charging: true, onAC: true)
        let (next, effects) = reduce(showing, .power(updated, at: 2.4))
        #expect(effects.isEmpty)
        guard case .showing(let show) = next.phase else {
            Issue.record("phase \(next.phase)")
            return
        }
        #expect(show.until == original.until)
        #expect(show.percent == 41)
        #expect(show.trigger == .chargerConnected)
    }

    @Test func lightsOffNeverShowsAndDismissesWhatIsUp() {
        var state = BatteryOverlayMachine()
        state = reduce(state, .power(unplugged, at: 0)).0
        state = reduce(state, .power(plugged, at: 1)).0
        let (dark, effects) = reduce(state, .setLights(false))
        #expect(effects == [.dismiss])
        #expect(dark.phase == .idle)
        #expect(!dark.lightsEnabled)
        let (_, again) = reduce(dark, .power(unplugged, at: 2))
        #expect(again.isEmpty)
        let (relit, none) = reduce(dark, .setLights(true))
        #expect(none.isEmpty)
        #expect(relit.phase == .idle)
        #expect(relit.lightsEnabled)
    }

    @Test func chargingWithoutAPlugChangeIsQuiet() {
        var state = BatteryOverlayMachine()
        let resting = BatteryPowerSample(percent: 50, charging: false, onAC: true)
        state = reduce(state, .power(resting, at: 0)).0
        let flipped = BatteryPowerSample(percent: 51, charging: true, onAC: true)
        let (_, effects) = reduce(state, .power(flipped, at: 5))
        #expect(effects.isEmpty)
    }

    @Test func unreadablePercentsDoNotShow() {
        let bad = [nil, -1, 101, 255]
        for percent in bad {
            let sample = BatteryPowerSample(percent: percent, charging: false, onAC: false)
            let (_, effects) = reduce(BatteryOverlayMachine(), .power(sample, at: 0))
            #expect(effects.isEmpty, "percent \(String(describing: percent)) showed \(effects)")
        }
    }

    @Test func advanceWhileIdleStaysIdle() {
        let (state, effects) = reduce(BatteryOverlayMachine(), .advance(to: 100))
        #expect(effects.isEmpty)
        #expect(state.phase == .idle)
    }

    @Test func reduceMotionZerosTheShowAndLeavesThePhases() {
        for motion in [false, true] {
            var state = BatteryOverlayMachine(reduceMotion: motion)
            state = reduce(state, .power(unplugged, at: 0)).0
            let (_, effects) = reduce(state, .power(plugged, at: 1))
            guard case .present(let show) = effects.first else {
                Issue.record("missing show")
                return
            }
            #expect(show.animationDuration == BatteryMotion.duration(reduceMotion: motion))
            #expect(motion ? show.animationDuration == 0 : show.animationDuration > 0)
        }
    }

    @Test func styleChangesTheNextShowAndDoesNotPresentByItself() {
        var state = BatteryOverlayMachine()
        let (styled, effects) = reduce(state, .setStyle(.ring))
        #expect(effects.isEmpty)
        #expect(styled.style == .ring)
        #expect(styled.phase == .idle)
        state = reduce(styled, .power(unplugged, at: 0)).0
        let (_, presented) = reduce(state, .power(plugged, at: 1))
        guard case .present(let show) = presented.first else {
            Issue.record("missing show")
            return
        }
        #expect(show.style == .ring)
    }

    @Test func everyPlugEdgeIsGuarded() {
        let flags = [false, true]
        for previousAC in flags {
            for nextAC in flags {
                for previousCharging in flags {
                    for nextCharging in flags {
                        for lights in flags {
                            var state = BatteryOverlayMachine(lightsEnabled: lights)
                            let previous = BatteryPowerSample(percent: 40, charging: previousCharging, onAC: previousAC)
                            state = reduce(state, .power(previous, at: 0)).0
                            let next = BatteryPowerSample(percent: 40, charging: nextCharging, onAC: nextAC)
                            let (_, effects) = reduce(state, .power(next, at: 1))
                            let expects = lights && previousAC != nextAC
                            #expect(effects.isEmpty != expects, "ac \(previousAC)->\(nextAC) charging \(previousCharging)->\(nextCharging) lights \(lights)")
                            if expects, case .present(let show) = effects.first {
                                #expect(show.trigger == (nextAC ? .chargerConnected : .chargerDisconnected))
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func lowBatteryBoundaries() {
        for percent in -2...12 {
            let sample = BatteryPowerSample(percent: percent, charging: false, onAC: false)
            let (_, effects) = reduce(BatteryOverlayMachine(), .power(sample, at: 0))
            let expects = (0...BatteryOverlayMachine.lowBatteryAt).contains(percent)
            #expect(effects.isEmpty != expects, "percent \(percent)")
        }
    }

    @Test func theHostPlanFollowsTheExistingCueAndGauge() {
        var state = BatteryOverlayMachine()
        state = reduce(state, .power(unplugged, at: 0)).0
        let connected = reduce(state, .power(plugged, at: 1)).1
        #expect(BatteryOverlayHostPlan.actions(for: connected) == [
            .showCharging(percent: 64, style: .gauge),
            .flashGauge(level: 0.64, charging: true),
        ])
        var onPower = BatteryOverlayMachine()
        onPower = reduce(onPower, .power(plugged, at: 0)).0
        let disconnected = reduce(onPower, .power(unplugged, at: 1)).1
        #expect(BatteryOverlayHostPlan.actions(for: disconnected) == [
            .flashGauge(level: 0.64, charging: false),
        ])
        let low = reduce(BatteryOverlayMachine(), .power(BatteryPowerSample(percent: 5, charging: false, onAC: false), at: 0)).1
        #expect(BatteryOverlayHostPlan.actions(for: low) == [
            .showLowBattery(percent: 5, style: .gauge),
        ])
        #expect(BatteryOverlayHostPlan.actions(for: [.dismiss]) == [.dismiss])
    }

    @Test func ringAndReadoutDoNotFlashTheGauge() {
        for style in [BatteryOverlayStyle.ring, .readout] {
            var state = BatteryOverlayMachine(style: style)
            state = reduce(state, .power(unplugged, at: 0)).0
            let effects = reduce(state, .power(plugged, at: 1)).1
            let actions = BatteryOverlayHostPlan.actions(for: effects)
            #expect(actions == [.showCharging(percent: 64, style: style)])
            #expect(!actions.contains(.flashGauge(level: 0.64, charging: true)))
        }
    }
}

@Suite("Battery overlay style")
struct BatteryOverlayStyleTests {
    @Test func theStyleDefaultsToTheGaugeAndFailsClosed() {
        #expect(BatteryOverlayStyle.default == .gauge)
        #expect(BatteryOverlayStyle.resolve("") == .gauge)
        #expect(BatteryOverlayStyle.resolve("gauge") == .gauge)
        #expect(BatteryOverlayStyle.resolve("ring") == .ring)
        #expect(BatteryOverlayStyle.resolve("readout") == .readout)
        #expect(BatteryOverlayStyle.resolve("nope") == .gauge)
        #expect(BatteryOverlayStyle.resolve("RING") == .gauge)
        #expect(BatteryOverlayStyle.storageKey == "battery.overlayStyle")
    }

    @Test func everyStyleHasATitleHelperAndVoiceOverLabel() {
        #expect(BatteryOverlayStyle.allCases.count == 3)
        for style in BatteryOverlayStyle.allCases {
            #expect(!style.title.isEmpty)
            #expect(!style.helper.isEmpty)
            #expect(!style.accessibilityLabel.isEmpty)
            #expect(!style.title.contains("—"))
            #expect(!style.helper.contains("—"))
            #expect(!style.helper.contains("–"))
        }
    }

    @Test func reduceMotionDurationIsZeroForEveryStyle() {
        for style in BatteryOverlayStyle.allCases {
            for motion in [false, true] {
                let duration = BatteryMotion.duration(reduceMotion: motion, style: style)
                if motion {
                    #expect(duration == 0)
                } else {
                    #expect(duration > 0)
                }
            }
        }
    }
}
