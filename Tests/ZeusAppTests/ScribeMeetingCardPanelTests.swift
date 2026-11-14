import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The panel puts one card on screen and takes it down only when the latest `render` asks for that. The fade is
/// injected here so a test decides when each fade ends.
@MainActor
@Suite("Meeting card panel")
struct ScribeMeetingCardPanelTests {
    @MainActor private final class Fades {
        var pending: [@MainActor @Sendable () -> Void] = []
        var targets: [CGFloat] = []
        func finishAll() {
            let run = pending
            pending = []
            for done in run { done() }
        }
    }

    private final class Screen {
        var frame = CGRect(x: -30_000, y: -30_000, width: 1440, height: 900)
    }

    private final class Taps {
        var primary: [ScribeMeetingCard] = []
        var cancel: [ScribeMeetingCard] = []
        var dismiss: [ScribeMeetingCard] = []
    }

    private func meeting(_ title: String) -> ScribeMeeting {
        let slot = ScribeCalendarSlot(id: title, title: title, start: Date(timeIntervalSince1970: 1_800_000_120),
                                      hasCallLink: true)
        return ScribeMeeting(key: title, title: title, callApp: .other("Synthetic"), slot: slot)
    }

    private func make(_ fades: Fades, _ taps: Taps = Taps(), _ screen: Screen = Screen()) -> ScribeMeetingCardPanel {
        ScribeMeetingCardPanel(
            actions: .init(primary: { taps.primary.append($0) }, cancel: { taps.cancel.append($0) },
                           dismiss: { taps.dismiss.append($0) }),
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            uptime: { 100 },
            // Far off every screen, so a test never flashes a window.
            visibleFrame: { screen.frame },
            fade: { _, alpha, done in
                fades.targets.append(alpha)
                if let done { fades.pending.append(done) }
            })
    }

    @Test func aFadeOutThatEndsAfterANewCardArrivedLeavesTheNewCardOnScreen() {
        let fades = Fades()
        let panel = make(fades)
        let first = ScribeMeetingCard.offer(meeting("First"), blocked: nil)
        let second = ScribeMeetingCard.offer(meeting("Second"), blocked: nil)
        panel.render(first)
        #expect(panel.isOnScreen)
        panel.render(.hidden)
        panel.render(second)
        fades.finishAll()
        #expect(panel.isOnScreen, "the card that arrived during the fade must stay")
        #expect(panel.drawnCard == second)
    }

    @Test func aFadeOutThatEndsWithNothingNewTakesTheCardDown() {
        let fades = Fades()
        let panel = make(fades)
        panel.render(.offer(meeting("First"), blocked: nil))
        panel.render(.hidden)
        #expect(panel.isOnScreen, "the card stays until the fade has run")
        fades.finishAll()
        #expect(!panel.isOnScreen)
        #expect(panel.drawnCard == .hidden)
    }

    @Test func onlyTheLatestHideTakesTheCardDownWhenHideShowHideInterleave() {
        let fades = Fades()
        let panel = make(fades)
        panel.render(.offer(meeting("First"), blocked: nil))
        panel.render(.hidden)
        let firstHide = fades.pending
        fades.pending = []
        panel.render(.offer(meeting("Second"), blocked: nil))
        panel.render(.hidden)
        let secondHide = fades.pending
        fades.pending = []
        for done in firstHide { done() }
        #expect(panel.isOnScreen, "the first hide was overtaken by later renders")
        for done in secondHide { done() }
        #expect(!panel.isOnScreen)
    }

    @Test func hidingWhatIsNotOnScreenDoesNothing() {
        let fades = Fades()
        let panel = make(fades)
        panel.render(.hidden)
        #expect(fades.targets.isEmpty)
        #expect(!panel.isOnScreen)
    }

    @Test func theButtonsDoNotAnswerWhileTheCardFadesOutAndAnswerAgainForANewCard() {
        let fades = Fades()
        let panel = make(fades)
        panel.render(.offer(meeting("First"), blocked: nil))
        #expect(panel.window?.ignoresMouseEvents == false)
        panel.render(.hidden)
        #expect(panel.window?.ignoresMouseEvents == true)
        panel.render(.offer(meeting("Second"), blocked: nil))
        #expect(panel.window?.ignoresMouseEvents == false)
    }

    /// Sends the key the way the window would receive it. Return is the primary button, Escape the cancel
    /// action (Cancel while counting down, the dismiss glyph otherwise): the real buttons answer, not a test closure.
    private func key(_ code: UInt16, _ character: String, in panel: ScribeMeetingCardPanel) throws {
        let window = try #require(panel.window)
        window.makeKey()
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: character,
            charactersIgnoringModifiers: character, isARepeat: false, keyCode: code))
        #expect(window.performKeyEquivalent(with: event), "key \(code) was not taken by a button")
    }

    @Test func everyButtonHandsOverTheCardTheViewDrew() async throws {
        let taps = Taps()
        let panel = make(Fades(), taps)
        defer { panel.window?.close() }
        let offer = ScribeMeetingCard.offer(meeting("First"), blocked: nil)
        panel.render(offer)
        try await Task.sleep(for: .seconds(0.3))
        try key(36, "\r", in: panel)
        try key(53, "\u{1b}", in: panel)
        let countdown = ScribeMeetingCard.countdown(meeting("Second"), seconds: 5, deadline: 105, total: 5)
        panel.render(countdown)
        try await Task.sleep(for: .seconds(0.3))
        try key(53, "\u{1b}", in: panel)
        #expect(taps.primary == [offer] && taps.dismiss == [offer] && taps.cancel == [countdown])
    }

    @Test func theCardStaysOnTheScreenItAppearedOnWhileItIsShown() {
        let screen = Screen()
        let fades = Fades()
        let panel = make(fades, Taps(), screen)
        panel.render(.offer(meeting("First"), blocked: nil))
        let first = panel.window?.frame.origin
        screen.frame = CGRect(x: -20_000, y: -20_000, width: 1440, height: 900)
        panel.render(.countdown(meeting("First"), seconds: 5, deadline: 105, total: 5))
        panel.render(.countdown(meeting("First"), seconds: 4, deadline: 105, total: 5))
        #expect(panel.window?.frame.origin == first, "a render must not move the card to another display")
        // A new appearance picks the screen again.
        panel.render(.hidden)
        fades.finishAll()
        panel.render(.offer(meeting("Second"), blocked: nil))
        #expect((panel.window?.frame.origin.x ?? 0) > -25_000, "the next appearance follows the screen of the day")
    }

    @Test func aScreenParameterChangeMovesTheCardWhereItIsShown() {
        let screen = Screen()
        let panel = make(Fades(), Taps(), screen)
        panel.render(.offer(meeting("First"), blocked: nil))
        screen.frame = CGRect(x: -20_000, y: -20_000, width: 1440, height: 900)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect((panel.window?.frame.origin.x ?? 0) > -25_000)
    }
}
