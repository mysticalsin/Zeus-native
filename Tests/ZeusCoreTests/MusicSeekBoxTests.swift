import Foundation
import Testing
@testable import ZeusCore

@Suite("Music seek box")
struct MusicSeekBoxTests {
    @Test func theShippedEndMargin() {
        #expect(MusicSeekBox.endMargin == 0.5)
        #expect(MusicSeekBox.endMarginStartsAfter == 1)
        #expect(MusicSeekBox.clampedTarget(240, duration: 240) == 240 - MusicSeekBox.endMargin)
    }

    @Test func aDragClampsToTheLine() {
        #expect(MusicSeekBox.fraction(x: 50, width: 200) == 0.25)
        #expect(MusicSeekBox.fraction(x: 0, width: 200) == 0)
        #expect(MusicSeekBox.fraction(x: 200, width: 200) == 1)
        #expect(MusicSeekBox.fraction(x: -10, width: 200) == 0)
        #expect(MusicSeekBox.fraction(x: 999, width: 200) == 1)
    }

    @Test func aMissingOrNonFiniteLineIsTheStart() {
        #expect(MusicSeekBox.fraction(x: 10, width: 0) == 0)
        #expect(MusicSeekBox.fraction(x: 10, width: -3) == 0)
        #expect(MusicSeekBox.fraction(x: 10, width: .nan) == 0)
        #expect(MusicSeekBox.fraction(x: 10, width: .infinity) == 0)
        #expect(MusicSeekBox.fraction(x: .nan, width: 200) == 0)
        #expect(MusicSeekBox.fraction(x: .infinity, width: 200) == 0)
        #expect(MusicSeekBox.fraction(x: -.infinity, width: 200) == 0)
    }

    @Test func secondsFollowTheClampedFraction() {
        #expect(MusicSeekBox.seconds(fraction: 0.5, duration: 240) == 120)
        #expect(MusicSeekBox.seconds(fraction: 0, duration: 240) == 0)
        #expect(MusicSeekBox.seconds(fraction: 1, duration: 240) == 240)
        #expect(MusicSeekBox.seconds(fraction: 1.5, duration: 240) == 240)
        #expect(MusicSeekBox.seconds(fraction: -1, duration: 240) == 0)
    }

    @Test func aNonFiniteFractionCannotSeek() {
        #expect(MusicSeekBox.seconds(fraction: .nan, duration: 100) == nil)
        #expect(MusicSeekBox.seconds(fraction: .infinity, duration: 100) == nil)
        #expect(MusicSeekBox.seconds(fraction: -.infinity, duration: 100) == nil)
    }

    @Test func aNonPositiveLengthCannotSeek() {
        #expect(MusicSeekBox.seconds(fraction: 0.5, duration: 0) == nil)
        #expect(MusicSeekBox.seconds(fraction: 0.5, duration: -5) == nil)
        #expect(MusicSeekBox.seconds(fraction: 0.5, duration: .nan) == nil)
    }

    @Test func aPositiveInfiniteLengthIsKept() {
        #expect(MusicSeekBox.seconds(fraction: 0.5, duration: .infinity) == .infinity)
        #expect(MusicSeekBox.seconds(fraction: 1, duration: .infinity) == .infinity)
        // Zero times infinity is not a time.
        #expect(MusicSeekBox.seconds(fraction: 0, duration: .infinity)?.isNaN == true)
    }

    @Test func elapsedDrawsWithinTheTrack() {
        #expect(MusicSeekBox.fraction(elapsed: 60, duration: 240) == 0.25)
        #expect(MusicSeekBox.fraction(elapsed: 0, duration: 240) == 0)
        #expect(MusicSeekBox.fraction(elapsed: 240, duration: 240) == 1)
        #expect(MusicSeekBox.fraction(elapsed: 300, duration: 240) == 1)
        #expect(MusicSeekBox.fraction(elapsed: -5, duration: 240) == 0)
        #expect(MusicSeekBox.fraction(elapsed: .infinity, duration: 10) == 1)
        #expect(MusicSeekBox.fraction(elapsed: -.infinity, duration: 10) == 0)
        #expect(MusicSeekBox.fraction(elapsed: .nan, duration: 10).isNaN)
    }

    @Test func aNonPositiveLengthDrawsAtTheStart() {
        #expect(MusicSeekBox.fraction(elapsed: 60, duration: 0) == 0)
        #expect(MusicSeekBox.fraction(elapsed: 60, duration: -4) == 0)
        #expect(MusicSeekBox.fraction(elapsed: 60, duration: .nan) == 0)
        #expect(MusicSeekBox.fraction(elapsed: 10, duration: .infinity) == 0)
    }

    @Test func aLongTrackStopsShortOfTheEnd() {
        #expect(MusicSeekBox.clampedTarget(240, duration: 240) == 239.5)
        #expect(MusicSeekBox.clampedTarget(239.5, duration: 240) == 239.5)
        #expect(MusicSeekBox.clampedTarget(100, duration: 240) == 100)
        #expect(MusicSeekBox.clampedTarget(2, duration: 2) == 1.5)
        #expect(MusicSeekBox.clampedTarget(.infinity, duration: 240) == 239.5)
    }

    @Test func aShortTrackMaySeekToItsEnd() {
        #expect(MusicSeekBox.clampedTarget(1, duration: 1) == 1)
        #expect(MusicSeekBox.clampedTarget(0.4, duration: 0.4) == 0.4)
        #expect(MusicSeekBox.clampedTarget(0, duration: 0.4) == 0)
    }

    @Test func aNegativeTargetOrLengthClampsToZero() {
        #expect(MusicSeekBox.clampedTarget(-5, duration: 240) == 0)
        #expect(MusicSeekBox.clampedTarget(-.infinity, duration: 240) == 0)
        #expect(MusicSeekBox.clampedTarget(10, duration: 0) == 0)
        #expect(MusicSeekBox.clampedTarget(10, duration: -4) == 0)
        #expect(MusicSeekBox.clampedTarget(.nan, duration: 240).isNaN)
        #expect(MusicSeekBox.clampedTarget(10, duration: .nan) == 10)
        #expect(MusicSeekBox.clampedTarget(10, duration: .infinity) == 10)
    }

    @Test func scriptsRoundToHundredths() {
        let spotify = "com.spotify.client"
        let music = "com.apple.Music"
        #expect(MusicSeekBox.script(bundleID: spotify, seconds: 83.456)
            == "tell application id \"com.spotify.client\" to set player position to 83.46")
        #expect(MusicSeekBox.script(bundleID: music, seconds: 12)
            == "tell application id \"com.apple.Music\" to set player position to 12.00")
        #expect(MusicSeekBox.script(bundleID: music, seconds: 83.454)
            == "tell application id \"com.apple.Music\" to set player position to 83.45")
        #expect(MusicSeekBox.script(bundleID: music, seconds: 0)
            == "tell application id \"com.apple.Music\" to set player position to 0.00")
        #expect(MusicSeekBox.script(bundleID: music, seconds: -3)
            == "tell application id \"com.apple.Music\" to set player position to 0.00")
        #expect(MusicSeekBox.script(bundleID: "", seconds: 1)
            == "tell application id \"\" to set player position to 1.00")
        #expect(MusicSeekBox.script(bundleID: music, seconds: .nan)
            == "tell application id \"\(music)\" to set player position to \(String(format: "%.2f", Double.nan))")
        #expect(MusicSeekBox.script(bundleID: music, seconds: .infinity)
            == "tell application id \"\(music)\" to set player position to \(String(format: "%.2f", Double.infinity))")
    }

    @Test func thePublicSeekReadsTheBox() {
        #expect(MusicSeek.fraction(x: 50, width: 200) == 0.25)
        #expect(MusicSeek.fraction(x: -10, width: 200) == 0)
        #expect(MusicSeek.fraction(x: 999, width: 200) == 1)
        #expect(MusicSeek.fraction(x: 10, width: 0) == 0)
        #expect(MusicSeek.seconds(fraction: 0.5, duration: 240) == 120)
        #expect(MusicSeek.seconds(fraction: 1.5, duration: 240) == 240)
        #expect(MusicSeek.seconds(fraction: -1, duration: 240) == 0)
        #expect(MusicSeek.seconds(fraction: 0.5, duration: 0) == nil)
        #expect(MusicSeek.seconds(fraction: .nan, duration: 100) == nil)
        #expect(MusicSeek.fraction(elapsed: 60, duration: 240) == 0.25)
        #expect(MusicSeek.fraction(elapsed: 60, duration: 0) == 0)
        #expect(MusicSeek.clampedTarget(240, duration: 240) == 239.5)
        #expect(MusicSeek.clampedTarget(-5, duration: 240) == 0)
        #expect(MusicSeek.clampedTarget(100, duration: 240) == 100)
        #expect(MusicSeek.script(player: .spotify, seconds: 83.456)
            == "tell application id \"com.spotify.client\" to set player position to 83.46")
        #expect(MusicSeek.script(player: .music, seconds: 12)
            == "tell application id \"com.apple.Music\" to set player position to 12.00")
        #expect(MusicSeek.script(player: .music, seconds: -3).hasSuffix("0.00"))
    }
}
