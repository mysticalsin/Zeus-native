import Foundation
import Testing
@testable import ZeusCore

@Suite("Teleprompter box")
struct TeleprompterBoxTests {
    private let sample = """
    # Intro
    Hi, I'm Tony.
    This is ZEUS.

    Second paragraph here.
    ## Demo
    Watch the notch.
    #
    """

    private func moment(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    @Test func blocksSplitCuesParagraphsAndDropAnEmptyCue() {
        let blocks = TeleprompterBox.blocks(in: sample)
        #expect(blocks.map(\.id) == [0, 1, 2, 3, 4])
        #expect(blocks.map(\.text) == ["Intro", "Hi, I'm Tony. This is ZEUS.", "Second paragraph here.", "Demo", "Watch the notch."])
        #expect(blocks.map(\.isCue) == [true, false, false, true, false])
        #expect(blocks.filter(\.isCue).map(\.text) == ["Intro", "Demo"])
    }

    @Test func anEmptyOrBlankScriptHasNoBlocks() {
        #expect(TeleprompterBox.blocks(in: "").isEmpty)
        #expect(TeleprompterBox.blocks(in: "   \n\n  ").isEmpty)
        #expect(TeleprompterBox.blocks(in: "#").isEmpty)
        #expect(TeleprompterBox.blocks(in: "#   ").isEmpty)
        #expect(TeleprompterBox.wordCount(in: "") == 0)
        #expect(TeleprompterBox.wordCount(in: "#\n# Intro") == 0)
    }

    @Test func aCueKeepsItsTitleAndAParagraphKeepsInteriorSpace() {
        let blocks = TeleprompterBox.blocks(in: "  ##  Demo \nHi,  I'm Tony.\nhello # there")
        #expect(blocks.map(\.isCue) == [true, false])
        #expect(blocks.map(\.text) == ["Demo", "Hi,  I'm Tony. hello # there"])
        #expect(TeleprompterBox.wordCount(in: "Hi,  I'm Tony.") == 3)
    }

    @Test func wordCountSkipsCuesAndAStoppedPaceIsZero() {
        #expect(TeleprompterBox.wordCount(in: sample) == 12)
        #expect(TeleprompterBox.readingTime(wordCount: 12, wordsPerMinute: 60) == 12)
        #expect(TeleprompterBox.readingTime(wordCount: 12, wordsPerMinute: 150) == 12.0 / 150.0 * 60)
        #expect(TeleprompterBox.readingTime(wordCount: 0, wordsPerMinute: 150) == 0)
        #expect(TeleprompterBox.readingTime(wordCount: 12, wordsPerMinute: 0) == 0)
        #expect(TeleprompterBox.readingTime(wordCount: 12, wordsPerMinute: -5) == 0)
        #expect(TeleprompterBox.readingTime(wordCount: 12, wordsPerMinute: .nan) == 0)
        #expect(TeleprompterBox.readingTime(wordCount: 12, wordsPerMinute: .infinity) == 0)
        #expect(TeleprompterBox.defaultWordsPerMinute == 150)
    }

    @Test func speedClampsFiniteValuesAndKeepsANonFiniteSpeed() {
        #expect(TeleprompterBox.speedRange == 8...120)
        #expect(TeleprompterBox.defaultSpeed == 32)
        #expect(TeleprompterBox.clampedSpeed(32) == 32)
        #expect(TeleprompterBox.clampedSpeed(8) == 8)
        #expect(TeleprompterBox.clampedSpeed(120) == 120)
        #expect(TeleprompterBox.clampedSpeed(7) == 8)
        #expect(TeleprompterBox.clampedSpeed(500) == 120)
        #expect(TeleprompterBox.clampedSpeed(.nan).isNaN)
        #expect(TeleprompterBox.clampedSpeed(.infinity) == 120)
        #expect(TeleprompterBox.clampedSpeed(-.infinity) == 8)
        var roll = TeleprompterBox.Roll(speed: 32)
        TeleprompterBox.adjustSpeed(&roll, by: -1000)
        #expect(roll.speed == 8)
        TeleprompterBox.adjustSpeed(&roll, by: .nan)
        #expect(roll.speed.isNaN)
    }

    @Test func countdownShowsThreeThenOneAndStaysAtLeastOne() {
        #expect(TeleprompterBox.countdownLength == 3)
        let start = moment(1_000)
        var roll = TeleprompterBox.Roll()
        #expect(TeleprompterBox.countdownRemaining(roll, at: start) == nil)
        TeleprompterBox.start(&roll, at: start, countdown: true)
        #expect(roll.phase == .countdown)
        #expect(TeleprompterBox.countdownRemaining(roll, at: start) == 3)
        #expect(TeleprompterBox.countdownRemaining(roll, at: start.addingTimeInterval(1)) == 2)
        #expect(TeleprompterBox.countdownRemaining(roll, at: start.addingTimeInterval(2.2)) == 1)
        #expect(TeleprompterBox.countdownRemaining(roll, at: start.addingTimeInterval(3)) == 1)
        #expect(TeleprompterBox.countdownRemaining(roll, at: start.addingTimeInterval(4)) == 1)
    }

    @Test func theRollWaitsThroughTheCountdownThenMoves() {
        let start = moment(1_000)
        var roll = TeleprompterBox.Roll(speed: 30, voiceFollow: false)
        TeleprompterBox.start(&roll, at: start, countdown: true)
        TeleprompterBox.tick(&roll, 0.1, at: start.addingTimeInterval(1), hovered: false, maxOffset: 500)
        #expect(roll.phase == .countdown)
        #expect(roll.offset == 0)
        TeleprompterBox.tick(&roll, 0.1, at: start.addingTimeInterval(3.1), hovered: false, maxOffset: 500)
        #expect(roll.phase == .rolling)
        #expect(abs(roll.offset - 3) < 0.001)
        #expect(TeleprompterBox.countdownRemaining(roll, at: start.addingTimeInterval(3.1)) == nil)
    }

    @Test func quietVoiceFollowHoldsAndAThresholdLevelSpeaks() {
        #expect(TeleprompterBox.defaultVoiceThreshold == 0.12)
        #expect(TeleprompterBox.defaultVoiceGrace == 0.7)
        let start = moment(1_000)
        var roll = TeleprompterBox.Roll(speed: 10, voiceFollow: true)
        TeleprompterBox.start(&roll, at: start, countdown: false)
        TeleprompterBox.tick(&roll, 1, at: start.addingTimeInterval(1), hovered: false, maxOffset: 500)
        #expect(roll.offset == 0)
        #expect(!TeleprompterBox.isSpeaking(roll, at: start))
        TeleprompterBox.hear(&roll, level: 0.119, at: start)
        #expect(!TeleprompterBox.isSpeaking(roll, at: start))
        roll.voiceGrace = 0.5
        TeleprompterBox.hear(&roll, level: 0.12, at: start)
        #expect(TeleprompterBox.isSpeaking(roll, at: start.addingTimeInterval(0.5)))
        #expect(!TeleprompterBox.isSpeaking(roll, at: start.addingTimeInterval(0.8)))
        TeleprompterBox.tick(&roll, 1, at: start.addingTimeInterval(0.5), hovered: false, maxOffset: 500)
        #expect(roll.offset == 10)
        TeleprompterBox.hear(&roll, level: 0.05, at: start.addingTimeInterval(0.5))
        TeleprompterBox.tick(&roll, 1, at: start.addingTimeInterval(2), hovered: false, maxOffset: 500)
        #expect(roll.offset == 10)
        #expect(!TeleprompterBox.isSpeaking(roll, at: start.addingTimeInterval(2)))
        TeleprompterBox.hear(&roll, level: .nan, at: start.addingTimeInterval(2))
        #expect(!TeleprompterBox.isSpeaking(roll, at: start.addingTimeInterval(2)))
    }

    @Test func hoverHoldsAndTheEndOfTheScriptFinishes() {
        let start = moment(1_000)
        var roll = TeleprompterBox.Roll(speed: 100, voiceFollow: false)
        TeleprompterBox.start(&roll, at: start, countdown: false)
        TeleprompterBox.tick(&roll, 1, at: start, hovered: true, maxOffset: 150)
        #expect(roll.offset == 0)
        #expect(roll.phase == .rolling)
        TeleprompterBox.tick(&roll, 1, at: start, hovered: false, maxOffset: 150)
        TeleprompterBox.tick(&roll, 1, at: start, hovered: false, maxOffset: 150)
        #expect(roll.offset == 150)
        #expect(roll.phase == .finished)
        #expect(!TeleprompterBox.isMoving(roll, at: start, hovered: false))
        TeleprompterBox.tick(&roll, 1, at: start, hovered: false, maxOffset: 150)
        #expect(roll.offset == 150)
    }

    @Test func jumpRejectsANegativeOrNonFinitePoint() {
        var finished = TeleprompterBox.Roll(phase: .finished, offset: 40, speed: 10, voiceFollow: false)
        TeleprompterBox.jump(&finished, to: -4)
        #expect(finished.offset == 0)
        #expect(finished.phase == .rolling)
        TeleprompterBox.jump(&finished, to: .nan)
        #expect(finished.offset == 0)
        #expect(finished.phase == .rolling)
        var idle = TeleprompterBox.Roll()
        TeleprompterBox.jump(&idle, to: 20)
        #expect(idle.offset == 20)
        #expect(idle.phase == .idle)
        TeleprompterBox.jump(&idle, to: .infinity)
        #expect(idle.offset == .infinity)
    }

    @Test func pauseResumeAndStopKeepTheVoiceClockApartFromThePhase() {
        let start = moment(1_000)
        var roll = TeleprompterBox.Roll(speed: 10, voiceFollow: false)
        TeleprompterBox.start(&roll, at: start, countdown: true)
        TeleprompterBox.hear(&roll, level: 1, at: start)
        TeleprompterBox.pause(&roll)
        #expect(roll.phase == .paused)
        #expect(TeleprompterBox.countdownRemaining(roll, at: start) == nil)
        #expect(TeleprompterBox.isSpeaking(roll, at: start))
        TeleprompterBox.resume(&roll)
        #expect(roll.phase == .rolling)
        TeleprompterBox.tick(&roll, 1, at: start, hovered: false, maxOffset: 500)
        #expect(roll.offset == 10)
        TeleprompterBox.stop(&roll)
        #expect(roll.phase == .idle)
        #expect(roll.offset == 0)
        #expect(TeleprompterBox.countdownRemaining(roll, at: start) == nil)
        #expect(TeleprompterBox.isSpeaking(roll, at: start))
        #expect(!TeleprompterBox.isMoving(roll, at: start, hovered: false))
        TeleprompterBox.start(&roll, at: start.addingTimeInterval(1), countdown: false)
        #expect(roll.phase == .rolling)
        #expect(!TeleprompterBox.isSpeaking(roll, at: start.addingTimeInterval(1)))
        TeleprompterBox.pause(&roll)
        TeleprompterBox.pause(&roll)
        #expect(roll.phase == .paused)
        var idle = TeleprompterBox.Roll()
        TeleprompterBox.resume(&idle)
        #expect(idle.phase == .idle)
        TeleprompterBox.stop(&idle)
        #expect(idle.phase == .idle)
    }

    @Test func aNewSectionRestartsARollAndKeepsAPauseOrCountdown() {
        let start = moment(1_000)
        var rolling = TeleprompterBox.Roll(speed: 40, voiceFollow: true)
        TeleprompterBox.start(&rolling, at: start, countdown: false)
        TeleprompterBox.tick(&rolling, 1, at: start, hovered: false, maxOffset: 500)
        #expect(rolling.offset == 0)
        TeleprompterBox.hear(&rolling, level: 1, at: start)
        TeleprompterBox.tick(&rolling, 1, at: start, hovered: false, maxOffset: 500)
        #expect(rolling.offset == 40)
        TeleprompterBox.restartSection(&rolling, at: start.addingTimeInterval(2))
        #expect(rolling.phase == .rolling)
        #expect(rolling.offset == 0)
        #expect(TeleprompterBox.isSpeaking(rolling, at: start.addingTimeInterval(2.3)))

        var paused = TeleprompterBox.Roll(speed: 40, voiceFollow: false)
        TeleprompterBox.start(&paused, at: start, countdown: false)
        TeleprompterBox.tick(&paused, 1, at: start, hovered: false, maxOffset: 500)
        TeleprompterBox.pause(&paused)
        TeleprompterBox.restartSection(&paused, at: start)
        #expect(paused.offset == 0)
        #expect(paused.phase == .paused)

        var countdown = TeleprompterBox.Roll(speed: 40, voiceFollow: false)
        TeleprompterBox.start(&countdown, at: start, countdown: true)
        TeleprompterBox.tick(&countdown, 1, at: start, hovered: false, maxOffset: 500)
        TeleprompterBox.restartSection(&countdown, at: start)
        #expect(countdown.phase == .countdown)
        #expect(countdown.offset == 0)
        #expect(TeleprompterBox.countdownRemaining(countdown, at: start) == 3)

        var finished = TeleprompterBox.Roll(speed: 40, voiceFollow: false)
        TeleprompterBox.start(&finished, at: start, countdown: false)
        TeleprompterBox.tick(&finished, 1, at: start, hovered: false, maxOffset: 20)
        #expect(finished.phase == .finished)
        TeleprompterBox.restartSection(&finished, at: start)
        #expect(finished.phase == .rolling)
        #expect(finished.offset == 0)
        #expect(TeleprompterBox.isSpeaking(finished, at: start))

        var idle = TeleprompterBox.Roll()
        TeleprompterBox.restartSection(&idle, at: start)
        #expect(idle.phase == .idle)
        #expect(idle.offset == 0)
    }

    @Test func aZeroOrBackwardStepDoesNotMove() {
        let start = moment(1_000)
        var roll = TeleprompterBox.Roll(speed: 10, voiceFollow: false)
        TeleprompterBox.start(&roll, at: start, countdown: false)
        TeleprompterBox.tick(&roll, 0, at: start, hovered: false, maxOffset: 500)
        TeleprompterBox.tick(&roll, -1, at: start, hovered: false, maxOffset: 500)
        #expect(roll.offset == 0)
        #expect(roll.phase == .rolling)
        TeleprompterBox.tick(&roll, 1, at: start, hovered: false, maxOffset: .infinity)
        #expect(roll.offset == 10)
        #expect(roll.phase == .rolling)
        TeleprompterBox.tick(&roll, 1, at: start, hovered: false, maxOffset: .nan)
        #expect(roll.offset == 0)
        #expect(roll.phase == .rolling)
        TeleprompterBox.tick(&roll, 1, at: start, hovered: false, maxOffset: 0)
        #expect(roll.offset == 0)
        #expect(roll.phase == .rolling)
        TeleprompterBox.tick(&roll, 1, at: start, hovered: false, maxOffset: -20)
        #expect(roll.offset == 0)
        #expect(roll.phase == .rolling)
    }

    @Test func countdownEndingUnderHoverOrVoiceFollow() {
        let start = moment(1_000)
        var hovered = TeleprompterBox.Roll(speed: 30, voiceFollow: false)
        TeleprompterBox.start(&hovered, at: start, countdown: true)
        TeleprompterBox.tick(&hovered, 0.5, at: start.addingTimeInterval(3), hovered: true, maxOffset: 500)
        #expect(hovered.phase == .rolling)
        #expect(hovered.offset == 0)
        #expect(TeleprompterBox.isSpeaking(hovered, at: start.addingTimeInterval(3)))

        var followed = TeleprompterBox.Roll(speed: 30, voiceFollow: true)
        TeleprompterBox.start(&followed, at: start, countdown: true)
        TeleprompterBox.tick(&followed, 0.5, at: start.addingTimeInterval(3), hovered: false, maxOffset: 500)
        #expect(followed.phase == .rolling)
        #expect(followed.offset == 15)
        #expect(TeleprompterBox.isSpeaking(followed, at: start.addingTimeInterval(3)))

        var covered = TeleprompterBox.Roll(speed: 30, voiceFollow: true)
        TeleprompterBox.start(&covered, at: start, countdown: true)
        TeleprompterBox.tick(&covered, 0.5, at: start.addingTimeInterval(3), hovered: true, maxOffset: 500)
        #expect(covered.phase == .rolling)
        #expect(covered.offset == 0)
        #expect(TeleprompterBox.isMoving(covered, at: start.addingTimeInterval(3), hovered: true) == false)
    }

    @Test func aFinishedRollResumesAndASecondBeginClearsTheOffset() {
        let start = moment(1_000)
        var roll = TeleprompterBox.Roll(speed: 20, voiceFollow: false)
        TeleprompterBox.start(&roll, at: start, countdown: false)
        TeleprompterBox.tick(&roll, 1, at: start, hovered: false, maxOffset: 20)
        #expect(roll.phase == .finished)
        TeleprompterBox.resume(&roll)
        #expect(roll.phase == .rolling)
        #expect(roll.offset == 20)
        TeleprompterBox.hear(&roll, level: 1, at: start)
        TeleprompterBox.start(&roll, at: start.addingTimeInterval(1), countdown: true)
        #expect(roll.phase == .countdown)
        #expect(roll.offset == 0)
        #expect(!TeleprompterBox.isSpeaking(roll, at: start.addingTimeInterval(1)))
        #expect(TeleprompterBox.countdownRemaining(roll, at: start.addingTimeInterval(1)) == 3)
    }

    @Test func thePublicScriptAndRollReadTheBox() {
        let script = PrompterScript(sample)
        let boxBlocks = TeleprompterBox.blocks(in: sample)
        #expect(script.blocks.map(\.id) == boxBlocks.map(\.id))
        #expect(script.blocks.map(\.text) == ["Intro", "Hi, I'm Tony. This is ZEUS.", "Second paragraph here.", "Demo", "Watch the notch."])
        #expect(script.blocks.map(\.isCue) == boxBlocks.map(\.isCue))
        #expect(script.cues.map(\.text) == ["Intro", "Demo"])
        #expect(script.wordCount == 12)
        #expect(script.wordCount == TeleprompterBox.wordCount(in: sample))
        #expect(abs(script.readingTime(wordsPerMinute: 60) - 12) < 0.001)
        #expect(script.readingTime() == TeleprompterBox.readingTime(wordCount: 12, wordsPerMinute: 150))

        let start = moment(1_000)
        var roll = PrompterRoll(speed: 500, voiceFollow: false)
        #expect(roll.speed == 120)
        #expect(roll.speed == PrompterRoll.speedRange.upperBound)
        #expect(PrompterRoll.countdownLength == 3)
        roll.adjustSpeed(by: -1000)
        #expect(roll.speed == PrompterRoll.speedRange.lowerBound)
        roll = PrompterRoll(speed: 30, voiceFollow: false)
        roll.start(at: start)
        #expect(roll.countdownRemaining(at: start) == 3)
        #expect(roll.countdownRemaining(at: start.addingTimeInterval(2.2)) == 1)
        roll.tick(0.1, at: start.addingTimeInterval(1), hovered: false, maxOffset: 500)
        #expect(roll.offset == 0)
        roll.tick(0.1, at: start.addingTimeInterval(3.1), hovered: false, maxOffset: 500)
        #expect(roll.phase == .rolling)
        #expect(abs(roll.offset - 3) < 0.001)

        var voice = PrompterRoll(speed: 10, voiceFollow: true)
        voice.start(at: start, countdown: false)
        voice.tick(1, at: start.addingTimeInterval(1), hovered: false, maxOffset: 500)
        #expect(voice.offset == 0)
        voice.hear(level: 0.5, at: start.addingTimeInterval(1))
        voice.tick(1, at: start.addingTimeInterval(1.5), hovered: false, maxOffset: 500)
        #expect(voice.offset == 10)
        voice.tick(1, at: start.addingTimeInterval(3), hovered: false, maxOffset: 500)
        #expect(voice.offset == 10)

        var ended = PrompterRoll(speed: 100, voiceFollow: false)
        ended.start(at: start, countdown: false)
        ended.tick(1, at: start, hovered: true, maxOffset: 150)
        #expect(ended.offset == 0)
        ended.tick(1, at: start, hovered: false, maxOffset: 150)
        ended.tick(1, at: start, hovered: false, maxOffset: 150)
        #expect(ended.offset == 150)
        #expect(ended.phase == .finished)
        ended.jump(to: 20)
        #expect(ended.phase == .rolling)
        #expect(ended.offset == 20)

        var fresh = PrompterRoll()
        #expect(fresh.speed == 32)
        #expect(fresh.voiceFollow)
        #expect(fresh.voiceThreshold == 0.12)
        #expect(fresh.voiceGrace == 0.7)
        #expect(fresh.phase == .idle)
        fresh.restartSection(at: start)
        #expect(fresh.phase == .idle)
    }
}
