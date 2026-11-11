import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

// Synthetic displays and a pure reducer: no AppKit, no capture, no sleeping.

private typealias Display = RecordlySourceSelection.CatalogSnapshot.Display

private let builtIn = Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                             stableID: "UUID-BUILTIN", name: "Built-in Retina Display", isMain: true)
private let external = Display(id: 7, frame: CGRect(x: 1512, y: -400, width: 2560, height: 1440),
                               stableID: "UUID-LG", name: "LG UltraFine", isMain: false)

@Suite("Recordly display choice")
struct RecordlyDisplayChoiceTests {
    @Test func mainDisplayIsSelectedByDefault() {
        let decision = RecordlyDisplayChoice.decide(displays: [external, builtIn], current: nil, remembered: nil)
        #expect(decision.selected == 1)
        #expect(decision.source == .main)
        #expect(!decision.lostCurrent)
    }

    @Test func aChoiceThatIsStillConnectedIsKept() {
        let decision = RecordlyDisplayChoice.decide(displays: [builtIn, external], current: 7, remembered: "UUID-BUILTIN")
        #expect(decision.selected == 7)
        #expect(decision.source == .current)
    }

    @Test func rememberedDisplayIsFoundByStableIdentityNotByRawId() {
        // The external monitor came back under a different CGDirectDisplayID.
        let replugged = Display(id: 42, frame: external.frame, stableID: "UUID-LG", name: "LG UltraFine")
        let decision = RecordlyDisplayChoice.decide(displays: [builtIn, replugged], current: nil, remembered: "UUID-LG")
        #expect(decision.selected == 42)
        #expect(decision.source == .remembered)
    }

    @Test func unpluggedRememberedDisplayFallsBackToMain() {
        let decision = RecordlyDisplayChoice.decide(displays: [builtIn], current: nil, remembered: "UUID-LG")
        #expect(decision.selected == 1)
        #expect(decision.source == .main)
    }

    @Test func unpluggingTheCurrentChoiceFallsBackToMainAndSaysSo() {
        let decision = RecordlyDisplayChoice.decide(displays: [builtIn], current: 7, remembered: nil)
        #expect(decision.selected == 1)
        #expect(decision.lostCurrent)
    }

    @Test func noMainFlagStillSelectsTheFirstDisplayAndNoDisplaysSelectsNothing() {
        let plain = Display(id: 9, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(RecordlyDisplayChoice.decide(displays: [plain], current: nil, remembered: nil).selected == 9)
        let none = RecordlyDisplayChoice.decide(displays: [], current: 7, remembered: "x")
        #expect(none.selected == nil)
        #expect(none.source == .none)
        #expect(none.lostCurrent)
    }

    @Test func placeholderIdZeroIsNeverChosen() {
        let zero = Display(id: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100), isMain: true)
        #expect(RecordlyDisplayChoice.decide(displays: [zero], current: nil, remembered: nil).selected == nil)
    }

    @Test func labelsNameTheDisplayAndMarkMain() {
        #expect(RecordlyDisplayChoice.compactLine(builtIn, position: 0) == "Built-in Retina Display, Main")
        #expect(RecordlyDisplayChoice.compactLine(external, position: 1) == "LG UltraFine")
        #expect(RecordlyDisplayChoice.size(builtIn) == "1512 \u{00D7} 982")
        #expect(RecordlyDisplayChoice.spokenLabel(builtIn, position: 0) == "Built-in Retina Display, 1512 \u{00D7} 982, main display")
        let unnamed = Display(id: 3, frame: CGRect(x: 0, y: 0, width: 800, height: 600), name: "  ")
        #expect(RecordlyDisplayChoice.title(unnamed, position: 1) == "Display 2")
    }

    @Test func arrangementIsProportionalAndKeepsTheRelativePosition() {
        let tiles = RecordlyDisplayChoice.arrangement([builtIn, external], in: CGSize(width: 400, height: 120), gap: 0)
        #expect(tiles.count == 2)
        let a = tiles[0].rect, b = tiles[1].rect
        #expect(abs(a.width / a.height - 1512.0 / 982.0) < 0.001)
        #expect(abs(b.width / b.height - 2560.0 / 1440.0) < 0.001)
        // Same scale for both, external is to the right and higher up (smaller y).
        #expect(abs(b.width / a.width - 2560.0 / 1512.0) < 0.001)
        #expect(b.minX >= a.maxX - 0.001)
        #expect(b.minY < a.minY)
        // Everything stays inside the bounds.
        for rect in [a, b] {
            #expect(rect.minX >= -0.001 && rect.minY >= -0.001 && rect.maxX <= 400.001 && rect.maxY <= 120.001)
        }
    }

    @Test func arrangementSkipsBrokenFramesAndEmptyBounds() {
        let broken = Display(id: 5, frame: CGRect(x: 0, y: 0, width: 0, height: 10))
        #expect(RecordlyDisplayChoice.arrangement([broken], in: CGSize(width: 100, height: 100)).isEmpty)
        #expect(RecordlyDisplayChoice.arrangement([builtIn], in: .zero).isEmpty)
    }
}

@Suite("Recordly countdown")
struct RecordlyCountdownTests {
    private func token(_ countdown: RecordlyCountdown) -> UInt64 {
        guard case .counting(_, let token) = countdown.state else { return 0 }
        return token
    }

    @Test func countsThreeTwoOneThenStartsCapture() {
        var countdown = RecordlyCountdown()
        var effects = countdown.send(.press(sourceReady: true))
        #expect(countdown.remaining == 3)
        #expect(effects == [.scheduleTick(token: token(countdown))])
        let t = token(countdown)
        effects = countdown.send(.tick(token: t))
        #expect(countdown.remaining == 2)
        #expect(effects == [.scheduleTick(token: t)])
        effects = countdown.send(.tick(token: t))
        #expect(countdown.remaining == 1)
        effects = countdown.send(.tick(token: t))
        #expect(effects == [.startCapture])
        #expect(countdown.state == .idle)
    }

    @Test func secondPressCancelsAndEscapeCancels() {
        var countdown = RecordlyCountdown()
        _ = countdown.send(.press(sourceReady: true))
        #expect(countdown.send(.press(sourceReady: true)) == [.cancelTick])
        #expect(countdown.state == .idle)
        _ = countdown.send(.press(sourceReady: true))
        #expect(countdown.send(.cancel) == [.cancelTick])
        #expect(countdown.state == .idle)
        #expect(countdown.send(.cancel).isEmpty)
    }

    @Test func aTickFromACancelledCountdownDoesNothing() {
        var countdown = RecordlyCountdown()
        _ = countdown.send(.press(sourceReady: true))
        let stale = token(countdown)
        _ = countdown.send(.cancel)
        #expect(countdown.send(.tick(token: stale)).isEmpty)
        _ = countdown.send(.press(sourceReady: true))
        // The new countdown has its own token, so the old timer still cannot advance it.
        #expect(token(countdown) != stale)
        #expect(countdown.send(.tick(token: stale)).isEmpty)
        #expect(countdown.remaining == 3)
    }

    @Test func pressWithoutASourceNeverStartsCounting() {
        var countdown = RecordlyCountdown()
        #expect(countdown.send(.press(sourceReady: false)) == [.notice(RecordlyCountdown.noSourceNotice)])
        #expect(countdown.state == .idle)
    }

    @Test func sourceUnpluggedMidCountdownReturnsToIdleWithANotice() {
        var countdown = RecordlyCountdown()
        _ = countdown.send(.press(sourceReady: true))
        _ = countdown.send(.tick(token: token(countdown)))
        let effects = countdown.send(.sourceUnavailable(reason: "LG UltraFine was disconnected."))
        #expect(effects == [.cancelTick, .notice("LG UltraFine was disconnected.")])
        #expect(countdown.state == .idle)
        // Nothing to cancel when idle.
        #expect(countdown.send(.sourceUnavailable(reason: "x")).isEmpty)
    }
}
