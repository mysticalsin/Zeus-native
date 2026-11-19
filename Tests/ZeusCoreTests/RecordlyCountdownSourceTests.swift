import Testing
@testable import ZeusCore

@Suite("Recordly countdown source loss")
struct RecordlyCountdownSourceTests {
    private func counting() -> (RecordlyCountdown, UInt64) {
        var countdown = RecordlyCountdown()
        let effects = countdown.send(.press(sourceReady: true))
        var token: UInt64 = 0
        if case .scheduleTick(let issued)? = effects.first { token = issued }
        return (countdown, token)
    }

    @Test func aTickWithTheSourceGoneEndsTheCountdownWithANoticeAndNeverStartsCapture() {
        var (countdown, token) = counting()
        let effects = countdown.send(.tick(token: token, sourceReady: false))
        #expect(effects == [.cancelTick, .notice(RecordlyCountdown.sourceLostNotice)])
        #expect(countdown.state == .idle)
    }

    @Test func theLastTickWithTheSourceGoneNoLongerEndsInASilentNoOp() {
        var (countdown, token) = counting()
        _ = countdown.send(.tick(token: token))
        _ = countdown.send(.tick(token: token))
        let last = countdown.send(.tick(token: token, sourceReady: false))
        #expect(!last.contains(.startCapture))
        #expect(last.contains(.notice(RecordlyCountdown.sourceLostNotice)))
    }

    @Test func tickingWithAValidSourceStillStartsCaptureOnTheLastStep() {
        var (countdown, token) = counting()
        _ = countdown.send(.tick(token: token))
        _ = countdown.send(.tick(token: token))
        let last = countdown.send(.tick(token: token, sourceReady: true))
        #expect(last == [.startCapture])
    }

    @Test func aStaleTokenIsIgnoredEvenWhenTheSourceIsGone() {
        var (countdown, token) = counting()
        let effects = countdown.send(.tick(token: token &+ 5, sourceReady: false))
        #expect(effects == [])
        #expect(countdown.isCounting)
    }

    @Test func leavingThePageCancelsTheCountdownAndAPendingTickDoesNothing() {
        // The page's onDisappear sends .cancel; the timer that already fired must not start recording.
        var (countdown, token) = counting()
        let cancel = countdown.send(.cancel)
        #expect(cancel == [.cancelTick])
        let late = countdown.send(.tick(token: token))
        #expect(late == [])
        #expect(!countdown.isCounting)
    }
}
