import Foundation
import Testing
@testable import ZeusCore

/// The shuffle and repeat press as a pure state machine: what shows at once, what is sent, what is read
/// back and which answers are dropped.
@Suite struct MusicModePressTests {
    private let sep = NowPlaying.probeSeparator

    // MARK: A known mode moves at once

    @Test func aKnownShufflePressFlipsAtOnceAndSendsTheNewValue() {
        var press = MusicModePress(control: .shuffle, player: .music)
        let start = press.press(current: MusicModes(shuffle: false, repeatMode: .all))
        #expect(start.optimistic == MusicModes(shuffle: true, repeatMode: .all))
        #expect(start.next == .send(script: MusicModeRules.setShuffleScript(player: .music, on: true)))
    }

    @Test func aKnownShuffleOnPressSendsOff() {
        var press = MusicModePress(control: .shuffle, player: .spotify)
        let start = press.press(current: MusicModes(shuffle: true, repeatMode: .off))
        #expect(start.optimistic == MusicModes(shuffle: false, repeatMode: .off))
        #expect(start.next == .send(script: MusicModeRules.setShuffleScript(player: .spotify, on: false)))
    }

    @Test func aKnownRepeatPressWrapsAndLeavesShuffleAlone() {
        var music = MusicModePress(control: .repeatMode, player: .music)
        let fromOne = music.press(current: MusicModes(shuffle: true, repeatMode: .one))
        #expect(fromOne.optimistic == MusicModes(shuffle: true, repeatMode: .off))
        #expect(fromOne.next == .send(script: MusicModeRules.setRepeatScript(player: .music, mode: .off)))

        var spotify = MusicModePress(control: .repeatMode, player: .spotify)
        let fromAll = spotify.press(current: MusicModes(shuffle: false, repeatMode: .all))
        #expect(fromAll.optimistic == MusicModes(shuffle: false, repeatMode: .off))
        #expect(fromAll.next == .send(script: MusicModeRules.setRepeatScript(player: .spotify, mode: .off)))
    }

    @Test func aKnownShuffleDoesNotNeedTheOtherModeToBeKnown() {
        var press = MusicModePress(control: .shuffle, player: .music)
        let start = press.press(current: MusicModes(shuffle: true, repeatMode: nil))
        #expect(start.optimistic == MusicModes(shuffle: false, repeatMode: nil))
        #expect(start.next == .send(script: MusicModeRules.setShuffleScript(player: .music, on: false)))
    }

    // MARK: An unknown mode is read first, and never guessed

    @Test func anUnknownShufflePressShowsNothingAndReadsFirst() {
        var press = MusicModePress(control: .shuffle, player: .music)
        let start = press.press(current: MusicModes())
        #expect(start.optimistic == nil)
        #expect(start.next == .readPlayer)
    }

    @Test func theFirstReadDecidesTheSend() {
        var press = MusicModePress(control: .shuffle, player: .music)
        _ = press.press(current: MusicModes())
        // Shuffle is really on, so the press turns it off. A guess from nil would have said on.
        let next = press.handle(.playerRead(MusicModes(shuffle: true, repeatMode: .off)))
        #expect(next == .send(script: MusicModeRules.setShuffleScript(player: .music, on: false)))
    }

    @Test func anUnknownRepeatPressSendsTheStepAfterWhatWasRead() {
        var press = MusicModePress(control: .repeatMode, player: .spotify)
        _ = press.press(current: MusicModes(shuffle: true, repeatMode: nil))
        let next = press.handle(.playerRead(MusicModes(shuffle: true, repeatMode: .all)))
        #expect(next == .send(script: MusicModeRules.setRepeatScript(player: .spotify, mode: .off)))
    }

    @Test func anUnreadableFirstReadSkipsTheSend() {
        var press = MusicModePress(control: .shuffle, player: .music)
        _ = press.press(current: MusicModes())
        #expect(press.handle(.playerRead(nil)) == .stop)
        #expect(press.phase == .finished)
        // Nothing may follow a stopped press.
        #expect(press.handle(.sent) == .stop)
    }

    @Test func aRepeatPressIsNotSentFromAReadThatLeftTheModeNil() {
        var press = MusicModePress(control: .repeatMode, player: .music)
        _ = press.press(current: MusicModes())
        #expect(press.handle(.playerRead(MusicModes(shuffle: true, repeatMode: nil))) == .stop)
    }

    @Test func aPlayerThatLeftBeforeTheFirstReadStopsThePress() {
        var press = MusicModePress(control: .shuffle, player: .music)
        _ = press.press(current: MusicModes())
        #expect(press.handle(.unavailable) == .stop)
    }

    // MARK: Read back

    @Test func aSendIsReadBackAndTheAnswerIsShown() {
        var press = MusicModePress(control: .shuffle, player: .music)
        _ = press.press(current: MusicModes(shuffle: false, repeatMode: .off))
        #expect(press.handle(.sent) == .readBack)
        let answer = "true\(sep)all"
        let next = press.handle(.readBack(output: answer, current: MusicModes(shuffle: true, repeatMode: .off), isCurrent: true))
        #expect(next == .show(MusicModes(shuffle: true, repeatMode: .all)))
        #expect(press.phase == .finished)
    }

    @Test func aStaleReadBackIsDropped() {
        var press = MusicModePress(control: .shuffle, player: .music)
        _ = press.press(current: MusicModes(shuffle: false, repeatMode: .off))
        _ = press.handle(.sent)
        let next = press.handle(.readBack(output: "true\(sep)off", current: MusicModes(shuffle: true, repeatMode: .off), isCurrent: false))
        #expect(next == .stop)
    }

    @Test func aReadBackThatFailedOutrightSendsTheControlBackToUnknown() {
        var press = MusicModePress(control: .shuffle, player: .music)
        _ = press.press(current: MusicModes(shuffle: false, repeatMode: .off))
        _ = press.handle(.sent)
        let next = press.handle(.readBack(output: nil, current: MusicModes(shuffle: true, repeatMode: .off), isCurrent: true))
        #expect(next == .show(MusicModes()))
    }

    @Test func aReadBackThatCannotBeParsedSendsTheControlBackToUnknown() {
        var press = MusicModePress(control: .repeatMode, player: .music)
        _ = press.press(current: MusicModes(shuffle: false, repeatMode: .off))
        _ = press.handle(.sent)
        let next = press.handle(.readBack(output: "garbage", current: MusicModes(shuffle: false, repeatMode: .all), isCurrent: true))
        #expect(next == .show(MusicModes()))
    }

    @Test func aPlayerThatLeftBeforeTheReadBackSendsTheControlBackToUnknown() {
        var press = MusicModePress(control: .shuffle, player: .music)
        _ = press.press(current: MusicModes(shuffle: false, repeatMode: .off))
        _ = press.handle(.sent)
        #expect(press.handle(.unavailable) == .show(MusicModes()))
    }

    @Test func aPlayerThatLeftBeforeTheSendKeepsWhatWasShown() {
        var press = MusicModePress(control: .shuffle, player: .music)
        _ = press.press(current: MusicModes(shuffle: false, repeatMode: .off))
        #expect(press.handle(.unavailable) == .stop)
    }

    // MARK: Order

    @Test func eventsOutOfOrderStopThePress() {
        var press = MusicModePress(control: .shuffle, player: .music)
        _ = press.press(current: MusicModes(shuffle: false, repeatMode: .off))
        // A read back before the send was made has no meaning.
        #expect(press.handle(.readBack(output: "true\(sep)off", current: MusicModes(), isCurrent: true)) == .stop)
    }

    @Test func aPressStartsOnlyOnce() {
        var press = MusicModePress(control: .shuffle, player: .music)
        _ = press.press(current: MusicModes(shuffle: false, repeatMode: .off))
        let again = press.press(current: MusicModes(shuffle: false, repeatMode: .off))
        #expect(again.optimistic == nil)
        #expect(again.next == .stop)
    }
}

/// The look of a toggle that is on: a shape and a contrast, never a tint alone.
@Suite struct ToggleOnLookTests {
    /// WCAG relative luminance of a grey or colour given as 0...1 channels.
    private func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private func ratio(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// White at `opacity` over the darkest panel (black), which is the weakest case for a light overlay.
    private func overBlack(_ opacity: Double) -> Double { luminance(opacity, opacity, opacity) }

    @Test func offHasNoCapsuleAndNoBorder() {
        #expect(ToggleOnLook.fill(active: false) == 0)
        #expect(ToggleOnLook.stroke(active: false) == 0)
    }

    @Test func onHasAFilledCapsuleAndABorder() {
        #expect(ToggleOnLook.fill(active: true) > 0)
        #expect(ToggleOnLook.stroke(active: true) > ToggleOnLook.fill(active: true))
    }

    @Test func theGlyphReadsOnTheOnCapsule() {
        // The primary tone, E9EDF2, over the capsule fill: text-grade contrast.
        let glyph = luminance(0xE9 / 255.0, 0xED / 255.0, 0xF2 / 255.0)
        #expect(ratio(glyph, overBlack(ToggleOnLook.fill(active: true))) >= 4.5)
    }

    @Test func theOnCapsuleEdgeStandsOutFromThePanel() {
        // Non-text contrast of the border against the panel behind it.
        #expect(ratio(overBlack(ToggleOnLook.stroke(active: true)), overBlack(0)) >= 3)
    }

    @Test func theOnCapsuleFillIsClearlyMoreThanTheOldFaintOne() {
        #expect(ToggleOnLook.fill(active: true) >= 0.28)
    }

    @Test func theSpokenStateIsOnOrOff() {
        #expect(ToggleOnLook.spoken(true) == "on")
        #expect(ToggleOnLook.spoken(false) == "off")
    }
}
