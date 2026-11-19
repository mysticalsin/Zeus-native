import Testing
import ZeusCore

@Suite("Local speech model preparation")
struct ModelPreparationTests {
    private typealias M = ModelPreparation

    private func start(_ state: M.State, token: UInt64 = 1, _ trigger: M.Trigger = .explicit,
                       downloaded: Bool = false, announce: Bool = true) -> (M.State, [M.Effect]) {
        M.reduce(state, .startRequested(token: token, trigger: trigger, downloaded: downloaded, announce: announce))
    }

    private func preparing(_ token: UInt64 = 1, fraction: Double = 0.4, downloading: Bool = true, announce: Bool = true) -> M.State {
        .preparing(token: token, fraction: fraction, downloading: downloading, announce: announce)
    }

    @Test func startFromIdleDownloadsAnnouncesAndBeginsWork() {
        let (state, effects) = start(.idle)
        #expect(state == preparing(1, fraction: 0))
        #expect(effects == [.startWork(token: 1, downloading: true), .announce(.downloading)])
    }

    @Test func startWithFilesOnDiskOnlyLoadsAndStaysQuiet() {
        let (state, effects) = start(.idle, downloaded: true, announce: false)
        #expect(state == preparing(1, fraction: 0, downloading: false, announce: false))
        #expect(effects == [.startWork(token: 1, downloading: false)])
    }

    @Test func silentDownloadDoesNotAnnounce() {
        let (_, effects) = start(.idle, announce: false)
        #expect(effects == [.startWork(token: 1, downloading: true)])
    }

    @Test func doubleStartWhilePreparingIsIgnored() {
        let (state, effects) = start(preparing(1), token: 2)
        #expect(state == preparing(1))
        #expect(effects.isEmpty)
    }

    @Test func progressMovesTheLiveTokenAndClamps() {
        #expect(M.reduce(preparing(1), .progress(token: 1, fraction: 0.8)).0 == preparing(1, fraction: 0.8))
        #expect(M.reduce(preparing(1), .progress(token: 1, fraction: 7)).0 == preparing(1, fraction: 1))
        #expect(M.reduce(preparing(1), .progress(token: 1, fraction: -1)).0 == preparing(1, fraction: 0))
    }

    @Test func staleProgressIsDropped() {
        #expect(M.reduce(preparing(2), .progress(token: 1, fraction: 0.9)).0 == preparing(2))
    }

    @Test func lateProgressAfterFinishCannotLeaveTheBarStuck() {
        let (ready, _) = M.reduce(preparing(1), .succeeded(token: 1))
        let (after, _) = M.reduce(ready, .progress(token: 1, fraction: 0.99))
        #expect(after == .ready)
        #expect(M.progress(of: after) == nil)
    }

    @Test func successAnnouncesOnlyAfterAVisibleDownload() {
        let r1 = M.reduce(preparing(1), .succeeded(token: 1))
        #expect(r1.0 == .ready)
        #expect(r1.1 == [.announce(.ready)])
        let r2 = M.reduce(preparing(1, downloading: false), .succeeded(token: 1))
        #expect(r2.0 == .ready)
        #expect(r2.1 == [])
        let r3 = M.reduce(preparing(1, announce: false), .succeeded(token: 1))
        #expect(r3.0 == .ready)
        #expect(r3.1 == [])
    }

    @Test func staleSuccessAndFailureAreIgnored() {
        #expect(M.reduce(preparing(2), .succeeded(token: 1)).0 == preparing(2))
        #expect(M.reduce(preparing(2), .failed(token: 1, message: "old")).0 == preparing(2))
        #expect(M.reduce(.idle, .succeeded(token: 1)).0 == .idle)
        #expect(M.reduce(.ready, .failed(token: 1, message: "late")).0 == .ready)
    }

    @Test func failureRecordsTheReasonAndAnnouncesIt() {
        let (state, effects) = M.reduce(preparing(1), .failed(token: 1, message: "offline"))
        #expect(state == .failed(message: "offline"))
        #expect(effects == [.announce(.failed(message: "offline"))])
        #expect(M.problem(of: state) == "offline")
        #expect(M.progress(of: state) == nil)
    }

    @Test func automaticRetryAfterFailureIsRefusedButExplicitRetryWorks() {
        let failed = M.State.failed(message: "offline")
        let (auto, autoEffects) = start(failed, token: 2, .automatic)
        #expect(auto == failed)
        #expect(autoEffects.isEmpty)
        let (retry, retryEffects) = start(failed, token: 2, .explicit)
        #expect(retry == preparing(2, fraction: 0))
        #expect(retryEffects.contains(.startWork(token: 2, downloading: true)))
        #expect(M.problem(of: retry) == nil)
    }

    @Test func automaticStartWhenReadyIsRefusedButExplicitReloads() {
        #expect(start(.ready, token: 2, .automatic, downloaded: true).0 == .ready)
        #expect(start(.ready, token: 2, .explicit, downloaded: true).0 == preparing(2, fraction: 0, downloading: false))
    }

    @Test func cancelFromPreparingStopsTheWorkAndReturnsToIdle() {
        let (state, effects) = M.reduce(preparing(5), .cancelRequested)
        #expect(state == .idle)
        #expect(effects == [.cancelWork(token: 5)])
    }

    @Test func cancelFromEveryOtherStateIsSafe() {
        let r4 = M.reduce(.idle, .cancelRequested)
        #expect(r4.0 == .idle)
        #expect(r4.1 == [])
        let r5 = M.reduce(.ready, .cancelRequested)
        #expect(r5.0 == .ready)
        #expect(r5.1 == [])
        let r6 = M.reduce(.failed(message: "x"), .cancelRequested)
        #expect(r6.0 == .idle)
        #expect(r6.1 == [])
    }

    @Test func completionArrivingAfterCancelIsDropped() {
        let (cancelled, _) = M.reduce(preparing(5), .cancelRequested)
        #expect(M.reduce(cancelled, .succeeded(token: 5)).0 == .idle)
        #expect(M.reduce(cancelled, .failed(token: 5, message: "cancelled")).0 == .idle)
        #expect(M.reduce(cancelled, .progress(token: 5, fraction: 0.5)).0 == .idle)
    }

    @Test func downloadAfterCancelStartsFreshUnderANewToken() {
        let (cancelled, _) = M.reduce(preparing(5), .cancelRequested)
        let (state, effects) = start(cancelled, token: 6, .automatic)
        #expect(state == preparing(6, fraction: 0))
        #expect(effects.contains(.startWork(token: 6, downloading: true)))
        // The cancelled run's late failure cannot touch the new one.
        #expect(M.reduce(state, .failed(token: 5, message: "cancelled")).0 == state)
    }
}
