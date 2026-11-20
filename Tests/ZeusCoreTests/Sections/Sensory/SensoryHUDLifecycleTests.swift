import Foundation
import Testing
@testable import ZeusCore

@Suite struct SensoryHUDLifecycleTests {
    private let start = Date(timeIntervalSinceReferenceDate: 10_000)

    private func at(_ offset: Double) -> Date { start.addingTimeInterval(offset) }

    private func config(
        volume: Bool = true,
        brightness: Bool = true,
        hold: Double = 1.2,
        reduceMotion: Bool = false
    ) -> SensoryHUDConfig {
        SensoryHUDConfig(
            settings: SensorySettings(volume: volume, brightness: brightness, hold: hold),
            reduceMotion: reduceMotion
        )
    }

    private func show(_ kind: SystemHUDKind = .volume, level: Double = 0.5, muted: Bool = false, at offset: Double = 0) -> SensoryHUDEvent {
        .changed(kind, level: level, muted: muted, at: at(offset))
    }

    @Test func phasesAreNamedInLifecycleOrder() {
        #expect(SensoryHUDPhase.allCases.map(\.rawValue) == ["hidden", "showing", "extending", "fading"])
    }

    @Test func hiddenStaysHiddenUntilAnAcceptedChange() {
        let rules = config()
        let (ticked, tickEffects) = SensoryHUDLifecycle.reduce(.hidden, .tick(at(1)), config: rules)
        let (dismissed, dismissEffects) = SensoryHUDLifecycle.reduce(.hidden, .dismiss, config: rules)
        let (edited, editEffects) = SensoryHUDLifecycle.reduce(.hidden, .configurationChanged(at(1)), config: rules)
        let (keyboard, keyboardEffects) = SensoryHUDLifecycle.reduce(.hidden, show(.keyboardBacklight), config: rules)
        let (dark, darkEffects) = SensoryHUDLifecycle.reduce(.hidden, show(.brightness), config: config(brightness: false))
        #expect(ticked == .hidden)
        #expect(dismissed == .hidden)
        #expect(edited == .hidden)
        #expect(keyboard == .hidden)
        #expect(dark == .hidden)
        #expect(tickEffects.isEmpty && dismissEffects.isEmpty && editEffects.isEmpty && keyboardEffects.isEmpty && darkEffects.isEmpty)
    }

    @Test func anAcceptedChangeShowsThenFadesThenHides() {
        let rules = config()
        let (shown, effects) = SensoryHUDLifecycle.reduce(.hidden, show(), config: rules)
        #expect(shown.phase == .showing)
        #expect(shown.kind == .volume)
        #expect(shown.level == 0.5)
        #expect(shown.anchor == start)
        #expect(shown.fadeAnchor == nil)
        #expect(effects == [.announce("Volume 50 percent"), .wake(at(0.12 + 1.2))])

        let (early, earlyEffects) = SensoryHUDLifecycle.reduce(shown, .tick(at(1.32 - 0.001)), config: rules)
        #expect(early.phase == .showing)
        #expect(earlyEffects.isEmpty)

        let (fading, fadeEffects) = SensoryHUDLifecycle.reduce(shown, .tick(at(1.32)), config: rules)
        #expect(fading.phase == .fading)
        #expect(fading.fadeAnchor == at(1.32))
        #expect(fadeEffects == [.wake(at(1.32 + 0.25))])

        let (still, stillEffects) = SensoryHUDLifecycle.reduce(fading, .tick(at(1.57 - 0.001)), config: rules)
        #expect(still.phase == .fading)
        #expect(stillEffects.isEmpty)

        let (gone, goneEffects) = SensoryHUDLifecycle.reduce(fading, .tick(at(1.57)), config: rules)
        #expect(gone == .hidden)
        #expect(goneEffects.isEmpty)

        let (caughtUp, _) = SensoryHUDLifecycle.reduce(shown, .tick(at(1.57)), config: rules)
        #expect(caughtUp == .hidden)
    }

    @Test func opacityRisesHoldsAndFalls() {
        let rules = config()
        let (shown, _) = SensoryHUDLifecycle.reduce(.hidden, show(), config: rules)
        #expect(SensoryHUDLifecycle.opacity(shown, at: at(0), config: rules) == 0)
        let midway = SensoryHUDLifecycle.opacity(shown, at: at(0.06), config: rules)
        #expect(abs(midway - 0.5) < 0.000_001)
        #expect(SensoryHUDLifecycle.opacity(shown, at: at(0.12), config: rules) == 1)
        #expect(SensoryHUDLifecycle.opacity(shown, at: at(1), config: rules) == 1)
        #expect(SensoryHUDLifecycle.opacity(shown, at: at(-1), config: rules) == 0)

        let (fading, _) = SensoryHUDLifecycle.reduce(shown, .tick(at(1.32)), config: rules)
        #expect(SensoryHUDLifecycle.opacity(fading, at: at(1.32), config: rules) == 1)
        let half = SensoryHUDLifecycle.opacity(fading, at: at(1.32 + 0.125), config: rules)
        #expect(abs(half - 0.5) < 0.000_001)
        #expect(SensoryHUDLifecycle.opacity(fading, at: at(1.57), config: rules) == 0)
        #expect(SensoryHUDLifecycle.opacity(.hidden, at: at(0), config: rules) == 0)
    }

    @Test func aRepeatChangeExtendsAtFullOpacity() {
        let rules = config()
        let (shown, _) = SensoryHUDLifecycle.reduce(.hidden, show(level: 0.2), config: rules)
        let change = at(0.02)
        let (extended, effects) = SensoryHUDLifecycle.reduce(shown, show(level: 0.8, at: 0.02), config: rules)
        #expect(extended.phase == .extending)
        #expect(extended.level == 0.8)
        #expect(extended.anchor == change)
        #expect(extended.fadeAnchor == nil)
        #expect(SensoryHUDLifecycle.opacity(extended, at: change, config: rules) == 1)
        #expect(effects == [.announce("Volume 80 percent"), .wake(change.addingTimeInterval(1.2))])

        let (still, _) = SensoryHUDLifecycle.reduce(extended, .tick(change.addingTimeInterval(1.2 - 0.001)), config: rules)
        #expect(still.phase == .extending)
        let (fading, _) = SensoryHUDLifecycle.reduce(extended, .tick(change.addingTimeInterval(1.2)), config: rules)
        #expect(fading.phase == .fading)
        let (gone, _) = SensoryHUDLifecycle.reduce(extended, .tick(change.addingTimeInterval(1.2 + 0.25)), config: rules)
        #expect(gone == .hidden)
    }

    @Test func aChangeDuringTheFadeComesBackAsExtending() {
        let rules = config()
        let (shown, _) = SensoryHUDLifecycle.reduce(.hidden, show(), config: rules)
        let (fading, _) = SensoryHUDLifecycle.reduce(shown, .tick(at(1.32)), config: rules)
        let (back, effects) = SensoryHUDLifecycle.reduce(fading, .changed(.brightness, level: 0.25, muted: false, at: at(1.4)), config: rules)
        #expect(back.phase == .extending)
        #expect(back.kind == .brightness)
        #expect(back.level == 0.25)
        #expect(back.fadeAnchor == nil)
        #expect(SensoryHUDLifecycle.opacity(back, at: at(1.4), config: rules) == 1)
        #expect(effects.contains(.announce("Brightness 25 percent")))
    }

    @Test func anotherExtendingChangeKeepsExtending() {
        let rules = config()
        let (shown, _) = SensoryHUDLifecycle.reduce(.hidden, show(), config: rules)
        let (once, _) = SensoryHUDLifecycle.reduce(shown, show(level: 0.7, at: 0.4), config: rules)
        let (twice, _) = SensoryHUDLifecycle.reduce(once, show(level: 0.9, muted: true, at: 0.5), config: rules)
        #expect(twice.phase == .extending)
        #expect(twice.muted)
        #expect(twice.anchor == at(0.5))
    }

    @Test func dismissHidesAndADisabledKindCannotShow() {
        let rules = config()
        let (shown, _) = SensoryHUDLifecycle.reduce(.hidden, show(), config: rules)
        let (gone, effects) = SensoryHUDLifecycle.reduce(shown, .dismiss, config: rules)
        #expect(gone == .hidden)
        #expect(effects.isEmpty)
        let (fromFade, _) = SensoryHUDLifecycle.reduce(
            SensoryHUDSnapshot(phase: .fading, kind: .volume, level: 0.4, muted: false, anchor: start, fadeAnchor: at(1)),
            .dismiss,
            config: rules
        )
        #expect(fromFade == .hidden)

        let off = config(volume: false)
        let (ignored, ignoredEffects) = SensoryHUDLifecycle.reduce(.hidden, show(), config: off)
        #expect(ignored == .hidden)
        #expect(ignoredEffects.isEmpty)
        let (hiding, _) = SensoryHUDLifecycle.reduce(shown, show(), config: off)
        #expect(hiding == .hidden)
        let (kept, _) = SensoryHUDLifecycle.reduce(shown, show(.brightness), config: config(volume: false))
        #expect(kept.phase == .extending)
        #expect(kept.kind == .brightness)
    }

    @Test func levelsThatAreNotFiniteOrInRangeAreClamped() {
        let rules = config()
        let (high, _) = SensoryHUDLifecycle.reduce(.hidden, show(level: 1.8), config: rules)
        #expect(high.level == 1)
        let (low, _) = SensoryHUDLifecycle.reduce(.hidden, show(level: -0.2), config: rules)
        #expect(low.level == 0)
        let (broken, _) = SensoryHUDLifecycle.reduce(.hidden, show(level: .nan), config: rules)
        #expect(broken.level == 0)
        let (infinite, _) = SensoryHUDLifecycle.reduce(.hidden, show(level: .infinity), config: rules)
        #expect(infinite.level == 0)
    }

    @Test func reduceMotionSkipsBothFades() {
        let rules = config(reduceMotion: true)
        let (shown, effects) = SensoryHUDLifecycle.reduce(.hidden, show(), config: rules)
        #expect(shown.phase == .showing)
        #expect(SensoryHUDLifecycle.opacity(shown, at: start, config: rules) == 1)
        #expect(effects == [.announce("Volume 50 percent"), .wake(at(1.2))])
        let (early, _) = SensoryHUDLifecycle.reduce(shown, .tick(at(1.2 - 0.001)), config: rules)
        #expect(early.phase == .showing)
        let (gone, goneEffects) = SensoryHUDLifecycle.reduce(shown, .tick(at(1.2)), config: rules)
        #expect(gone == .hidden)
        #expect(goneEffects.isEmpty)
        let stay = SensoryHUDLifecycle.timeUntilHidden(shown, now: start, config: rules)
        #expect(abs(stay - 1.2) < 0.000_001)
    }

    @Test func timeUntilHiddenMatchesTheTickThatHides() {
        let rules = config()
        let (shown, _) = SensoryHUDLifecycle.reduce(.hidden, show(), config: rules)
        let stay = SensoryHUDLifecycle.timeUntilHidden(shown, now: start, config: rules)
        #expect(abs(stay - (0.12 + 1.2 + 0.25)) < 0.000_001)
        let (during, _) = SensoryHUDLifecycle.reduce(shown, .tick(start.addingTimeInterval(stay - 0.001)), config: rules)
        #expect(during.phase == .fading)
        let (done, _) = SensoryHUDLifecycle.reduce(shown, .tick(start.addingTimeInterval(stay)), config: rules)
        #expect(done.phase == .hidden)

        let (extended, _) = SensoryHUDLifecycle.reduce(shown, show(at: 0.4), config: rules)
        let extendedStay = SensoryHUDLifecycle.timeUntilHidden(extended, now: at(0.4), config: rules)
        #expect(abs(extendedStay - (1.2 + 0.25)) < 0.000_001)
        #expect(SensoryHUDLifecycle.timeUntilHidden(.hidden, now: start, config: rules) == 0)
    }

    @Test func editingTheHoldMovesTheDeadlineAndDoesNotReviveAFade() {
        let rules = config(hold: 1.2)
        let (shown, _) = SensoryHUDLifecycle.reduce(.hidden, show(), config: rules)
        let longer = config(hold: 4)
        let (kept, effects) = SensoryHUDLifecycle.reduce(shown, .configurationChanged(at(1)), config: longer)
        #expect(kept.phase == .showing)
        #expect(effects == [.wake(at(0.12 + 4))])

        let shorter = config(hold: 0.4)
        let (advanced, advancedEffects) = SensoryHUDLifecycle.reduce(shown, .configurationChanged(at(0.6)), config: shorter)
        #expect(advanced.phase == .fading)
        #expect(advanced.fadeAnchor == at(0.12 + 0.4))
        #expect(advancedEffects == [.wake(at(0.12 + 0.4 + 0.25))])
        let (finished, _) = SensoryHUDLifecycle.reduce(shown, .configurationChanged(at(1)), config: shorter)
        #expect(finished == .hidden)

        let (fading, _) = SensoryHUDLifecycle.reduce(shown, .tick(at(1.32)), config: rules)
        let (stillFading, fadeEffects) = SensoryHUDLifecycle.reduce(fading, .configurationChanged(at(1.4)), config: longer)
        #expect(stillFading.phase == .fading)
        #expect(stillFading.fadeAnchor == at(1.32))
        #expect(fadeEffects == [.wake(at(1.57))])

        let turnedOff = config(volume: false)
        let (hidden, _) = SensoryHUDLifecycle.reduce(shown, .configurationChanged(at(0.2)), config: turnedOff)
        #expect(hidden == .hidden)
    }

    @Test func aSnapshotWithNoAnchorHidesOnTheNextTick() {
        let broken = SensoryHUDSnapshot(phase: .showing, kind: .volume, level: 0.4, muted: false, anchor: nil, fadeAnchor: nil)
        let (gone, _) = SensoryHUDLifecycle.reduce(broken, .tick(at(1)), config: config())
        #expect(gone == .hidden)
    }

    @Test func theLivePreviewFollowsThePhaseAndTheLabel() {
        let rules = SensoryHUDConfig(settings: SensorySettings(label: .words), reduceMotion: false)
        let (shown, _) = SensoryHUDLifecycle.reduce(.hidden, show(level: 0.42), config: rules)
        let frame = SensoryPreview.frame(settings: rules.settings, trusted: true, reading: false, snapshot: shown, now: start, reduceMotion: false)
        #expect(frame.status == .live)
        #expect(frame.hudPhase == .showing)
        #expect(frame.words == "Volume 42%")
        #expect(frame.symbol == nil)
        #expect(frame.opacity == 0)
        #expect(frame.error == nil)
    }
}

@Suite struct SensoryHUDPropertyTests {
    @Test func randomWalksStayInsideTheFourStates() {
        var generator = SensoryRNG(state: 0x5E45_071D)
        let kinds: [SystemHUDKind] = [.volume, .brightness, .keyboardBacklight]
        for _ in 0..<64 {
            var state = SensoryHUDSnapshot.hidden
            var now = Date(timeIntervalSinceReferenceDate: 50_000)
            var rules = SensoryHUDConfig(settings: SensorySettings(hold: 0.4 + generator.unit() * 5.6), reduceMotion: generator.bool())
            for _ in 0..<24 {
                let roll = generator.next() % 5
                let event: SensoryHUDEvent
                switch roll {
                case 0:
                    event = .changed(kinds[Int(generator.next() % 3)], level: generator.unit() * 1.5 - 0.2, muted: generator.bool(), at: now)
                case 1:
                    event = .tick(now)
                case 2:
                    event = .dismiss
                case 3:
                    rules.settings.volume = generator.bool()
                    rules.settings.brightness = generator.bool()
                    rules.settings.hold = SensoryHUDHold.clamp(generator.unit() * 8)
                    rules.reduceMotion = generator.bool()
                    event = .configurationChanged(now)
                default:
                    event = .tick(now.addingTimeInterval(-2))
                }
                let previous = state
                let (next, effects) = SensoryHUDLifecycle.reduce(state, event, config: rules)
                #expect(SensoryHUDPhase.allCases.contains(next.phase))
                #expect(next.level.isFinite && next.level >= 0 && next.level <= 1)
                let opacity = SensoryHUDLifecycle.opacity(next, at: now, config: rules)
                #expect(opacity >= 0 && opacity <= 1)
                #expect(SensoryHUDLifecycle.timeUntilHidden(next, now: now, config: rules) >= 0)
                switch next.phase {
                case .hidden:
                    #expect(next.kind == nil && next.anchor == nil && next.fadeAnchor == nil)
                    #expect(opacity == 0)
                case .showing, .extending:
                    #expect(next.kind == .volume || next.kind == .brightness)
                    #expect(next.anchor != nil && next.fadeAnchor == nil)
                case .fading:
                    #expect(next.kind == .volume || next.kind == .brightness)
                    #expect(next.fadeAnchor != nil)
                }
                if previous.phase == .hidden {
                    switch event {
                    case .changed(let kind, _, _, _) where SensoryHUDLifecycle.accepts(kind, rules.settings):
                        #expect(next.phase == .showing)
                    default:
                        #expect(next.phase == .hidden)
                    }
                }
                if next.phase == .extending {
                    #expect(previous.phase != .hidden)
                }
                if next.phase == .fading {
                    #expect(previous.phase == .showing || previous.phase == .extending || previous.phase == .fading)
                }
                for effect in effects {
                    if case .wake(let date) = effect {
                        #expect(date >= now)
                    }
                }
                state = next
                now = now.addingTimeInterval(generator.unit() * 0.4)
            }
        }
    }
}
