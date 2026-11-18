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

    @Test func theRealReaderUsesTheBoundedHelperLimits() {
        #expect(SystemNowPlayingProcess.timeout == SystemNowPlayingLaunch.timeout)
        #expect(SystemNowPlayingProcess.maxOutputBytes == SystemNowPlayingLaunch.maxOutputBytes)
    }
}
