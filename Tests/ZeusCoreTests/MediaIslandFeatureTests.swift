import Foundation
import Testing
@testable import ZeusCore

@Suite("Media island features")
struct MediaIslandFeatureTests {
    @Test func systemNowPlayingIsOffUntilAskedAndParsesThePerlLine() {
        #expect(MediaIslandFeatures.systemNowPlaying.enabled == false)
        #expect(MediaIslandFeatures.systemNowPlaying.permission == nil)
        #expect(SystemNowPlayingAdapter.command.last == "now-playing.pl")
        let line = SystemNowPlayingAdapter.parse("Night Drive\tAda\tCoast\t1\t12.5\t180\n")
        #expect(line == SystemNowPlayingLine(title: "Night Drive", artist: "Ada", album: "Coast", playing: true, position: 12.5, duration: 180))
        #expect(SystemNowPlayingAdapter.parse("nope") == nil)
    }

    @Test func theEarbudOverlayNeedsBluetoothAndStartsOff() {
        #expect(MediaIslandFeatures.earbudOverlay.enabled == false)
        #expect(MediaIslandFeatures.earbudOverlay.permission == .bluetooth)
        #expect(MediaIslandFeatures.earbudOverlay.usageStringKey == "NSBluetoothAlwaysUsageDescription")
    }

    @Test func theLockScreenPlayerUsesAPrivateSpaceAndAsksForNothing() {
        #expect(MediaIslandFeatures.lockScreenPlayer.enabled == false)
        #expect(MediaIslandFeatures.lockScreenPlayer.permission == nil)
        #expect(LockScreenPlayerSpace.isPrivateWindowServer)
        #expect(LockScreenPlayerSpace.collectsInput == false)
    }

    @Test func focusNameNeedsFullDiskAccessAndStartsOff() {
        #expect(MediaIslandFeatures.focusName.enabled == false)
        #expect(MediaIslandFeatures.focusName.permission == .fullDiskAccess)
        #expect(FocusNameReader.parse("Work") == "Work")
        #expect(FocusNameReader.parse("  ") == nil)
    }

    @Test func receiverNamesNeedLocalNetworkAndStartOff() {
        #expect(MediaIslandFeatures.receiverNames.enabled == false)
        #expect(MediaIslandFeatures.receiverNames.permission == .localNetwork)
        #expect(MediaIslandFeatures.receiverNames.usageStringKey == "NSLocalNetworkUsageDescription")
        #expect(ReceiverNames.bonjourTypes == ["_airplay._tcp", "_raop._tcp"])
        #expect(ReceiverNames.displayName(service: "Living Room", recordHexPrefix: "AABBCCDDEEFF@Living Room") == "Living Room")
    }

    @Test func facePresenceStoresNoPassword() throws {
        let record = FaceRecord(id: "1", name: "Owner", isEnabled: true, revision: 1, samples: [[0.1, 0.2]], threshold: 0.3)
        let data = try JSONEncoder().encode(record)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["password"] == nil)
        #expect(FacePresenceSecretPolicy.storesPassword == false)
    }

    @Test func pauseCollapsesThePlayerAndDevicesHaveIcons() {
        #expect(PlaybackCollapse.collapsed(paused: true, enabled: true))
        #expect(!PlaybackCollapse.collapsed(paused: false, enabled: true))
        #expect(!PlaybackCollapse.collapsed(paused: true, enabled: false))
        #expect(OutputDeviceIcon.symbol(for: .speakers) == "speaker.wave.2.fill")
        #expect(OutputDeviceIcon.symbol(for: .headphones) == "headphones")
        #expect(OutputDeviceIcon.symbol(for: .receiver) == "airplayaudio")
    }

    @Test func wordsShareTheLineIntervalExactly() {
        let words = WordTiming.words("one two three", start: 1, end: 4)
        #expect(words.map(\.text) == ["one", "two", "three"])
        #expect(words.first?.start == 1)
        #expect(words.last?.end == 4)
        #expect(words[1].start == words[0].end)
    }
}
