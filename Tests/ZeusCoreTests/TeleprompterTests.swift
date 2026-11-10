import Foundation
import Testing
@testable import ZeusCore

@Suite("Teleprompter")
struct TeleprompterTests {
    let sample = """
    # Intro
    Hi, I'm Tony.
    This is ZEUS.

    Second paragraph here.
    ## Demo
    Watch the notch.
    #
    """

    @Test func blocksSplitCuesAndParagraphs() {
        let blocks = PrompterScript(sample).blocks
        #expect(blocks.map(\.text) == ["Intro", "Hi, I'm Tony. This is ZEUS.", "Second paragraph here.", "Demo", "Watch the notch."])
        #expect(blocks.map(\.isCue) == [true, false, false, true, false])
        #expect(PrompterScript(sample).cues.map(\.text) == ["Intro", "Demo"])
    }

    @Test func wordCountSkipsCues() {
        let script = PrompterScript(sample)
        #expect(script.wordCount == 12)
        #expect(abs(script.readingTime(wordsPerMinute: 60) - 12) < 0.001)
    }

    @Test func countdownThenRolls() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var roll = PrompterRoll(speed: 30, voiceFollow: false)
        roll.start(at: t0)
        #expect(roll.countdownRemaining(at: t0) == 3)
        #expect(roll.countdownRemaining(at: t0.addingTimeInterval(2.2)) == 1)
        roll.tick(0.1, at: t0.addingTimeInterval(1), hovered: false, maxOffset: 500)
        #expect(roll.offset == 0)
        roll.tick(0.1, at: t0.addingTimeInterval(3.1), hovered: false, maxOffset: 500)
        #expect(roll.phase == .rolling)
        #expect(abs(roll.offset - 3) < 0.001)
    }

    @Test func voiceFollowHoldsWhenQuiet() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var roll = PrompterRoll(speed: 10, voiceFollow: true)
        roll.start(at: t0, countdown: false)
        roll.tick(1, at: t0.addingTimeInterval(1), hovered: false, maxOffset: 500)
        #expect(roll.offset == 0)
        roll.hear(level: 0.5, at: t0.addingTimeInterval(1))
        roll.tick(1, at: t0.addingTimeInterval(1.5), hovered: false, maxOffset: 500)
        #expect(roll.offset == 10)
        roll.tick(1, at: t0.addingTimeInterval(3), hovered: false, maxOffset: 500)
        #expect(roll.offset == 10)
        roll.hear(level: 0.05, at: t0.addingTimeInterval(3))
        #expect(!roll.isSpeaking(at: t0.addingTimeInterval(3)))
    }

    @Test func hoverPausesAndEndFinishes() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var roll = PrompterRoll(speed: 100, voiceFollow: false)
        roll.start(at: t0, countdown: false)
        roll.tick(1, at: t0, hovered: true, maxOffset: 150)
        #expect(roll.offset == 0)
        roll.tick(1, at: t0, hovered: false, maxOffset: 150)
        roll.tick(1, at: t0, hovered: false, maxOffset: 150)
        #expect(roll.offset == 150)
        #expect(roll.phase == .finished)
        roll.jump(to: 20)
        #expect(roll.phase == .rolling)
        #expect(roll.offset == 20)
    }

    @Test func speedIsClamped() {
        var roll = PrompterRoll(speed: 500)
        #expect(roll.speed == PrompterRoll.speedRange.upperBound)
        roll.adjustSpeed(by: -1000)
        #expect(roll.speed == PrompterRoll.speedRange.lowerBound)
    }
}
