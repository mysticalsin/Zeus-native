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

    private func make(_ fades: Fades, _ taps: Taps = Taps()) -> ScribeMeetingCardPanel {
        ScribeMeetingCardPanel(
            actions: .init(primary: { taps.primary.append($0) }, cancel: { taps.cancel.append($0) },
                           dismiss: { taps.dismiss.append($0) }),
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            uptime: { 100 },
            // Far off every screen, so a test never flashes a window.
            visibleFrame: { CGRect(x: -30_000, y: -30_000, width: 1440, height: 900) },
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

    @Test func everyTapCarriesTheCardTheViewDrew() throws {
        let fades = Fades()
        let taps = Taps()
        let panel = make(fades, taps)
        let card = ScribeMeetingCard.offer(meeting("First"), blocked: nil)
        panel.render(card)
        let view = try #require(panel.hostedView)
        #expect(view.card == card)
        view.onPrimary(view.card)
        view.onCancel(view.card)
        view.onDismiss(view.card)
        #expect(taps.primary == [card] && taps.cancel == [card] && taps.dismiss == [card])
    }
}
