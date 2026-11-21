import Foundation
import Testing
@testable import ZeusCore

@Suite("Push-to-talk indicator")
struct PTTIndicatorTests {
    private func sample(held: Bool = false, listening: Bool = false, level: Double = 0, failed: Bool = false) -> PTTIndicatorInput {
        PTTIndicatorInput(held: held, listening: listening, level: level, failed: failed)
    }

    @Test func holdArmsThenListensAndDoesNotToggle() {
        var model = PTTIndicatorModel()
        #expect(model.state == .idle)
        #expect(model.needsClock(at: 0, reduceMotion: false) == false)
        #expect(model.advance(sample(), now: 0, reduceMotion: false) == nil)
        #expect(model.state == .idle)

        #expect(model.advance(sample(held: true), now: 0.1, reduceMotion: false) == nil)
        #expect(model.state == .armed)

        #expect(model.advance(sample(held: true, listening: true, level: 0.5), now: 0.2, reduceMotion: false) == "Listening")
        #expect(model.state == .listening(level: 0.5))

        #expect(model.advance(sample(held: true, listening: true, level: 0.25), now: 0.3, reduceMotion: false) == nil)
        #expect(model.state == .listening(level: 0.25))

        #expect(model.advance(sample(), now: 0.4, reduceMotion: false) == "Stopped listening")
        #expect(model.state == .releasing)
        #expect(model.advance(sample(), now: 0.41, reduceMotion: false) == nil)
        #expect(model.state == .releasing)
    }

    @Test func reduceMotionStaysStaticWithNoPulse() {
        var model = PTTIndicatorModel()
        #expect(model.advance(sample(held: true, listening: true, level: 0.5), now: 0, reduceMotion: true) == "Listening")
        let early = model.frame(at: 0, reduceMotion: true)
        let later = model.frame(at: 4, reduceMotion: true)
        #expect(early.pulse == 0)
        #expect(later.pulse == 0)
        #expect(early.barSweep == later.barSweep)
        #expect(early.barOpacity == 1)
        #expect(early.orbOpacity == 1)
        #expect(early.ringScale == later.ringScale)
        #expect(model.needsClock(at: 0, reduceMotion: true) == false)
        #expect(model.needsClock(at: 4, reduceMotion: true) == false)

        #expect(model.advance(sample(), now: 4.1, reduceMotion: true) == "Stopped listening")
        #expect(model.state == .idle)
        #expect(model.frame(at: 4.1, reduceMotion: true).orbOpacity == 0)
        #expect(model.frame(at: 4.1, reduceMotion: true).barOpacity == 0)
        #expect(model.frame(at: 4.1, reduceMotion: true).pulse == 0)
        #expect(model.needsClock(at: 4.1, reduceMotion: true) == false)
    }

    @Test func levelClampsTheRing() {
        #expect(PTTIndicatorMotion.clampLevel(2) == 1)
        #expect(PTTIndicatorMotion.clampLevel(-0.5) == 0)
        #expect(PTTIndicatorMotion.clampLevel(.nan) == 0)
        #expect(PTTIndicatorMotion.clampLevel(.infinity) == 0)
        #expect(PTTIndicatorMotion.ringScale(level: 2) == PTTIndicatorMotion.ringScale(level: 1))
        #expect(PTTIndicatorMotion.ringScale(level: -3) == PTTIndicatorMotion.ringRest)
        #expect(PTTIndicatorMotion.ringScale(level: 1) <= PTTIndicatorMotion.ringRest + PTTIndicatorMotion.ringGain + 1e-9)

        var model = PTTIndicatorModel()
        _ = model.advance(sample(held: true, listening: true, level: 2), now: 0, reduceMotion: false)
        #expect(model.state == .listening(level: 1))
        let loud = model.frame(at: 0.3, reduceMotion: false).ringScale
        _ = model.advance(sample(held: true, listening: true, level: -4), now: 0.3, reduceMotion: false)
        #expect(model.state == .listening(level: 0))
        let quiet = model.frame(at: 0.3, reduceMotion: false).ringScale
        #expect(abs(loud - PTTIndicatorMotion.ringScale(level: 1)) < 1e-9)
        #expect(abs(quiet - PTTIndicatorMotion.ringScale(level: 0)) < 1e-9)
        #expect(loud > quiet)
    }

    @Test func releaseClearsWithinOneFrameBudget() {
        var model = PTTIndicatorModel()
        _ = model.advance(sample(held: true, listening: true, level: 0.75), now: 0, reduceMotion: false)
        let phrase = model.advance(sample(), now: 1, reduceMotion: false)
        #expect(phrase == "Stopped listening")
        #expect(model.state == .releasing)

        let soon = model.frame(at: 1 + PTTIndicatorMotion.frameBudget, reduceMotion: false)
        #expect(soon.orbOpacity < 1)
        #expect(soon.barOpacity < 1)
        #expect(soon.pulse == 0)

        let almost = 1 + PTTIndicatorMotion.exitDuration - PTTIndicatorMotion.frameBudget
        #expect(model.advance(sample(), now: almost, reduceMotion: false) == nil)
        #expect(model.state == .releasing)

        #expect(model.advance(sample(), now: 1 + PTTIndicatorMotion.exitDuration, reduceMotion: false) == nil)
        #expect(model.state == .idle)
        let gone = model.frame(at: 1 + PTTIndicatorMotion.exitDuration, reduceMotion: false)
        #expect(gone.orbOpacity == 0)
        #expect(gone.barOpacity == 0)
        #expect(gone.pulse == 0)
        #expect(model.needsClock(at: 1 + PTTIndicatorMotion.exitDuration, reduceMotion: false) == false)
        #expect(PTTIndicatorMotion.exitDuration == 0.15)
    }

    @Test func errorLeavesNoLingeringClock() {
        var model = PTTIndicatorModel()
        _ = model.advance(sample(held: true, listening: true, level: 0.75), now: 1, reduceMotion: false)
        let phrase = model.advance(sample(held: true, listening: true, level: 0.75, failed: true), now: 1.2, reduceMotion: false)
        #expect(phrase == "Stopped listening")
        #expect(model.state == .error)
        #expect(model.needsClock(at: 1.2, reduceMotion: false) == false)
        let stuck = model.frame(at: 9, reduceMotion: false)
        #expect(stuck.pulse == 0)
        #expect(stuck.orbOpacity == 0)
        #expect(stuck.barOpacity == 0)
        #expect(model.advance(sample(failed: true), now: 9.1, reduceMotion: false) == nil)
        #expect(model.state == .error)
        #expect(model.needsClock(at: 9.1, reduceMotion: false) == false)
        #expect(model.advance(sample(), now: 9.2, reduceMotion: false) == nil)
        #expect(model.state == .idle)
        #expect(model.needsClock(at: 9.2, reduceMotion: false) == false)

        #expect(PTTIndicatorFailure.isPublished(PTTIndicatorFailure.microphoneKeptChanging))
        #expect(PTTIndicatorFailure.isPublished(PTTIndicatorFailure.recordingTooLong))
        #expect(PTTIndicatorFailure.isPublished("Copied") == false)
        #expect(PTTIndicatorFailure.isPublished(nil) == false)
    }

    @Test func announcementsFireOncePerTransition() {
        var model = PTTIndicatorModel()
        var heard: [String] = []
        func take(_ input: PTTIndicatorInput, _ now: TimeInterval) {
            if let phrase = model.advance(input, now: now, reduceMotion: false) {
                heard.append(phrase)
            }
        }
        take(sample(held: true), 0)
        take(sample(held: true, listening: true, level: 0.25), 0.1)
        take(sample(held: true, listening: true, level: 0.75), 0.2)
        take(sample(held: true, listening: true, level: 0.5), 0.3)
        take(sample(), 0.4)
        take(sample(), 0.45)
        take(sample(held: true, listening: true, level: 0.25), 1)
        take(sample(held: true, failed: true), 1.1)
        take(sample(failed: true), 1.2)
        #expect(heard == ["Listening", "Stopped listening", "Listening", "Stopped listening"])

        var armed = PTTIndicatorModel()
        #expect(armed.advance(sample(held: true), now: 0, reduceMotion: false) == nil)
        #expect(armed.advance(sample(held: true, failed: true), now: 0.1, reduceMotion: false) == nil)
        #expect(armed.state == .error)
    }

    @Test func entryIsASpringBetween180And240ms() {
        #expect(PTTIndicatorMotion.entryDuration >= 0.18)
        #expect(PTTIndicatorMotion.entryDuration <= 0.24)
        #expect(PTTIndicatorMotion.entryDamping < 1)
        #expect(PTTIndicatorMotion.springRemaining(at: 0, response: PTTIndicatorMotion.entryResponse, damping: PTTIndicatorMotion.entryDamping) == 1)
        let overshoot = PTTIndicatorMotion.springRemaining(
            at: 0.16, response: PTTIndicatorMotion.entryResponse, damping: PTTIndicatorMotion.entryDamping)
        #expect(overshoot < 0)

        var model = PTTIndicatorModel()
        _ = model.advance(sample(held: true, listening: true, level: 0.25), now: 0, reduceMotion: false)
        let start = model.frame(at: 0, reduceMotion: false)
        let settled = model.frame(at: PTTIndicatorMotion.entryDuration, reduceMotion: false)
        #expect(start.barOpacity < 0.05)
        #expect(start.orbOpacity < 0.05)
        #expect(settled.barOpacity > 0.95)
        #expect(settled.orbOpacity > 0.95)
        #expect(model.needsClock(at: 0, reduceMotion: false))
        #expect(model.needsClock(at: PTTIndicatorMotion.entryDuration, reduceMotion: false) == false)
    }

    @Test func theRoundMarkStaysInsideTheExistingPanel() {
        var model = PTTIndicatorModel()
        _ = model.advance(sample(held: true, listening: true, level: 1), now: 0, reduceMotion: true)
        let frame = model.frame(at: 0, reduceMotion: true)
        #expect(frame.opensWindow == false)
        #expect(frame.surface == .existingNotchPanel)
        #expect(frame.orbX >= 0 && frame.orbX <= PTTIndicatorMotion.barWidth)
        #expect(frame.orbY >= 0 && frame.orbY <= PTTIndicatorMotion.barHeight)
        #expect(frame.contrast >= 4.5)
        #expect(PTTIndicatorContrast.ringOnNotch >= 4.5)
        #expect(frame.accessibilityLabel == "Listening")
        let idle = PTTIndicatorModel().frame(at: 0, reduceMotion: false)
        #expect(idle.accessibilityLabel.isEmpty)
        #expect(idle.opensWindow == false)
    }
}
