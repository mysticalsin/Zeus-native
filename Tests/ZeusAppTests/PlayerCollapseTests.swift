import Foundation
import Testing
import ZeusCore
@testable import Zeus

@MainActor
@Suite("Player collapse")
struct PlayerCollapseTests {
    @Test func theSettingStartsOff() {
        #expect(SettingsCatalog.option(PlaybackCollapse.settingID)?.defaultValue == "false")
    }

    @Test func aPausedItemOnTheRealModelCollapsesOnlyWhenTheSettingIsOn() {
        let suite = NSTemporaryDirectory() + "PlayerCollapseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TopBarModel(defaults: defaults)
        let source = NowPlayingSource.player(.music)
        model.nowPlaying = NowPlaying(source: source, title: "Song", artist: "Band", album: "Record",
                                      isPlaying: false, duration: 180, position: 10)
        #expect(PlayerChrome.collapsed(model: model, settingOn: true))
        model.nowPlaying = NowPlaying(source: source, title: "Song", artist: "Band", album: "Record",
                                      isPlaying: true, duration: 180, position: 10)
        #expect(!PlayerChrome.collapsed(model: model, settingOn: true))
        model.nowPlaying = nil
        #expect(!PlayerChrome.collapsed(model: model, settingOn: true))
    }
}
