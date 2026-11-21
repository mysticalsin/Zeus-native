import Foundation
import Testing
import ZeusCore
@testable import Zeus

@MainActor
@Suite("System now playing feed")
struct SystemNowPlayingFeedTests {
    @Test func aParsedLineReachesTheModelAndStoppingClearsIt() {
        let suite = NSTemporaryDirectory() + "SystemNowPlayingFeedTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TopBarModel(defaults: defaults)
        let hub = NowPlayingHub(model: model)
        let feed = SystemNowPlayingFeed(hub: hub, read: { "Night Drive\tAda\tCoast\t1\t12.5\t180\n" })
        feed.setEnabled(true)
        #expect(model.nowPlaying?.title == "Night Drive")
        #expect(model.nowPlaying?.source == .system)
        feed.setEnabled(false)
        #expect(model.nowPlaying == nil)
    }

    @Test func stopTerminatesTheHelper() async throws {
        let task = Task.detached {
            SystemNowPlayingProcess.run("/bin/sleep", ["30"], timeout: 5, maxOutputBytes: 32)
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !SystemNowPlayingProcess.isHelperRunning, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(SystemNowPlayingProcess.isHelperRunning)
        SystemNowPlayingProcess.stop()
        let result = await task.value
        #expect(result.status != 0)
        #expect(!SystemNowPlayingProcess.isHelperRunning)
    }

    @Test func theRealReaderUsesTheBoundedHelperLimits() {
        #expect(SystemNowPlayingProcess.timeout == SystemNowPlayingLaunch.timeout)
        #expect(SystemNowPlayingProcess.maxOutputBytes == SystemNowPlayingLaunch.maxOutputBytes)
    }
}
