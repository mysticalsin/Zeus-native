import Foundation
import Testing
@testable import ZeusCore

@Suite("Recordly countdown box")
struct RecordlyCountdownBoxTests {
    @Test func theCountdownIsThreeSeconds() {
        #expect(RecordlyCountdownBox.seconds == 3)
    }

    @Test func theNoticesNameTheMissingSourceAndTheLostSource() {
        #expect(RecordlyCountdownBox.noSourceNotice == "Choose a display or window first.")
        #expect(RecordlyCountdownBox.sourceLostNotice == "The source went away before recording started. Choose it again.")
    }

    @Test func aReadyPressSchedulesTheFirstTickAtThree() {
        var machine = RecordlyCountdownBox.Machine()
        let effects = RecordlyCountdownBox.send(&machine, .press(sourceReady: true))
        #expect(effects == [.scheduleTick(token: 1)])
        #expect(machine.state == .counting(remaining: 3, token: 1))
        #expect(machine.remaining == 3)
        #expect(machine.isCounting)
        #expect(machine.nextToken == 1)
    }

    @Test func threeTicksCountDownThenStartCapture() {
        var machine = RecordlyCountdownBox.Machine()
        _ = RecordlyCountdownBox.send(&machine, .press(sourceReady: true))
        #expect(RecordlyCountdownBox.send(&machine, .tick(token: 1)) == [.scheduleTick(token: 1)])
        #expect(machine.state == .counting(remaining: 2, token: 1))
        #expect(RecordlyCountdownBox.send(&machine, .tick(token: 1)) == [.scheduleTick(token: 1)])
        #expect(machine.remaining == 1)
        #expect(RecordlyCountdownBox.send(&machine, .tick(token: 1, sourceReady: true)) == [.startCapture])
        #expect(machine.state == .idle)
        #expect(machine.remaining == nil)
        #expect(!machine.isCounting)
    }

    @Test func aPressWithoutASourceDoesNotCountAndDoesNotSpendAToken() {
        var machine = RecordlyCountdownBox.Machine()
        #expect(RecordlyCountdownBox.send(&machine, .press(sourceReady: false)) == [.notice(RecordlyCountdownBox.noSourceNotice)])
        #expect(machine.state == .idle)
        #expect(machine.nextToken == 0)
        #expect(!machine.isCounting)
        #expect(RecordlyCountdownBox.send(&machine, .press(sourceReady: true)) == [.scheduleTick(token: 1)])
        #expect(machine.state == .counting(remaining: 3, token: 1))
    }

    @Test func aSecondPressCancelsEvenWhenTheSourceIsGone() {
        var machine = RecordlyCountdownBox.Machine()
        _ = RecordlyCountdownBox.send(&machine, .press(sourceReady: true))
        #expect(RecordlyCountdownBox.send(&machine, .press(sourceReady: false)) == [.cancelTick])
        #expect(machine.state == .idle)
        #expect(machine.nextToken == 1)
        #expect(RecordlyCountdownBox.send(&machine, .press(sourceReady: true)) == [.scheduleTick(token: 2)])
    }

    @Test func escapeCancelsAndASecondEscapeDoesNothing() {
        var machine = RecordlyCountdownBox.Machine()
        _ = RecordlyCountdownBox.send(&machine, .press(sourceReady: true))
        #expect(RecordlyCountdownBox.send(&machine, .cancel) == [.cancelTick])
        #expect(machine.state == .idle)
        #expect(RecordlyCountdownBox.send(&machine, .cancel) == [])
        #expect(machine.state == .idle)
    }

    @Test func aStaleTokenDoesNothingEvenWhenTheSourceIsGone() {
        var machine = RecordlyCountdownBox.Machine()
        _ = RecordlyCountdownBox.send(&machine, .press(sourceReady: true))
        #expect(RecordlyCountdownBox.send(&machine, .tick(token: 9, sourceReady: false)) == [])
        #expect(machine.state == .counting(remaining: 3, token: 1))
        #expect(machine.isCounting)
    }

    @Test func aLateTickAfterCancelDoesNotStartCapture() {
        var machine = RecordlyCountdownBox.Machine()
        _ = RecordlyCountdownBox.send(&machine, .press(sourceReady: true))
        #expect(RecordlyCountdownBox.send(&machine, .cancel) == [.cancelTick])
        #expect(RecordlyCountdownBox.send(&machine, .tick(token: 1)) == [])
        #expect(RecordlyCountdownBox.send(&machine, .tick(token: 1, sourceReady: false)) == [])
        #expect(machine.state == .idle)
        #expect(!machine.isCounting)
    }

    @Test func theSourceGoingAwayMidCountCancelsWithTheLostSourceNotice() {
        var machine = RecordlyCountdownBox.Machine()
        _ = RecordlyCountdownBox.send(&machine, .press(sourceReady: true))
        _ = RecordlyCountdownBox.send(&machine, .tick(token: 1))
        let effects = RecordlyCountdownBox.send(&machine, .tick(token: 1, sourceReady: false))
        #expect(effects == [.cancelTick, .notice(RecordlyCountdownBox.sourceLostNotice)])
        #expect(!effects.contains(.startCapture))
        #expect(machine.state == .idle)
    }

    @Test func theLastTickWithTheSourceGoneDoesNotStartCapture() {
        var machine = RecordlyCountdownBox.Machine()
        _ = RecordlyCountdownBox.send(&machine, .press(sourceReady: true))
        _ = RecordlyCountdownBox.send(&machine, .tick(token: 1))
        _ = RecordlyCountdownBox.send(&machine, .tick(token: 1))
        #expect(machine.remaining == 1)
        let last = RecordlyCountdownBox.send(&machine, .tick(token: 1, sourceReady: false))
        #expect(last == [.cancelTick, .notice(RecordlyCountdownBox.sourceLostNotice)])
        #expect(machine.state == .idle)
    }

    @Test func anUnavailableSourceUsesTheCallerReasonAndThenStaysIdle() {
        var machine = RecordlyCountdownBox.Machine()
        _ = RecordlyCountdownBox.send(&machine, .press(sourceReady: true))
        let effects = RecordlyCountdownBox.send(&machine, .sourceUnavailable(reason: "LG UltraFine was disconnected."))
        #expect(effects == [.cancelTick, .notice("LG UltraFine was disconnected.")])
        #expect(machine.state == .idle)
        #expect(RecordlyCountdownBox.send(&machine, .sourceUnavailable(reason: "x")) == [])
        #expect(machine.state == .idle)
    }

    @Test func idleIgnoresTicksCancelsAndSourceLoss() {
        var machine = RecordlyCountdownBox.Machine()
        #expect(RecordlyCountdownBox.send(&machine, .tick(token: 1)) == [])
        #expect(RecordlyCountdownBox.send(&machine, .tick(token: 1, sourceReady: false)) == [])
        #expect(RecordlyCountdownBox.send(&machine, .cancel) == [])
        #expect(RecordlyCountdownBox.send(&machine, .sourceUnavailable(reason: "gone")) == [])
        #expect(machine.state == .idle)
        #expect(machine.remaining == nil)
        #expect(machine.nextToken == 0)
        #expect(!machine.isCounting)
    }

    @Test func aWrappedTokenStartsAgainAtZero() {
        var machine = RecordlyCountdownBox.Machine(nextToken: UInt64.max)
        #expect(RecordlyCountdownBox.send(&machine, .press(sourceReady: true)) == [.scheduleTick(token: 0)])
        #expect(machine.state == .counting(remaining: 3, token: 0))
        #expect(machine.nextToken == 0)
    }

    @Test func aHandBuiltLastStepStartsCaptureAndAEarlierStepCountsDown() {
        var last = RecordlyCountdownBox.Machine(state: .counting(remaining: 1, token: 4), nextToken: 4)
        #expect(RecordlyCountdownBox.send(&last, .tick(token: 4)) == [.startCapture])
        #expect(last.state == .idle)
        #expect(last.nextToken == 4)

        var earlier = RecordlyCountdownBox.Machine(state: .counting(remaining: 2, token: 4), nextToken: 4)
        #expect(RecordlyCountdownBox.send(&earlier, .tick(token: 4)) == [.scheduleTick(token: 4)])
        #expect(earlier.state == .counting(remaining: 1, token: 4))

        var zero = RecordlyCountdownBox.Machine(state: .counting(remaining: 0, token: 8), nextToken: 8)
        #expect(RecordlyCountdownBox.send(&zero, .tick(token: 8, sourceReady: true)) == [.startCapture])
        #expect(zero.state == .idle)
    }

    @Test func aSuppliedTokenAdvancesFromThatValue() {
        var machine = RecordlyCountdownBox.Machine(nextToken: 5)
        #expect(RecordlyCountdownBox.send(&machine, .press(sourceReady: true)) == [.scheduleTick(token: 6)])
        #expect(machine.nextToken == 6)
        #expect(RecordlyCountdownBox.send(&machine, .cancel) == [.cancelTick])
        #expect(machine.nextToken == 6)
        #expect(RecordlyCountdownBox.send(&machine, .press(sourceReady: true)) == [.scheduleTick(token: 7)])
    }
}
