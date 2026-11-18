import Foundation
import Testing
@testable import ZeusCore

@Suite("Canopy parity")
struct CanopyParityTests {
    @Test func systemNowPlayingIsOffUntilAskedAndParsesThePerlLine() {
        #expect(CanopyFeatures.systemNowPlaying.enabled == false)
        #expect(CanopyFeatures.systemNowPlaying.permission == nil)
        #expect(SystemNowPlayingAdapter.command.last == "now-playing.pl")
        let line = SystemNowPlayingAdapter.parse("Night Drive\tAda\tCoast\t1\t12.5\t180\n")
        #expect(line == SystemNowPlayingLine(title: "Night Drive", artist: "Ada", album: "Coast", playing: true, position: 12.5, duration: 180))
        #expect(SystemNowPlayingAdapter.parse("nope") == nil)
    }

    @Test func airPodsOverlayNeedsBluetoothAndStartsOff() {
        #expect(CanopyFeatures.airPodsOverlay.enabled == false)
        #expect(CanopyFeatures.airPodsOverlay.permission == .bluetooth)
        #expect(CanopyFeatures.airPodsOverlay.usageStringKey == "NSBluetoothAlwaysUsageDescription")
    }

    @Test func theLockScreenPlayerUsesAPrivateSpaceAndAsksForNothing() {
        #expect(CanopyFeatures.lockScreenPlayer.enabled == false)
        #expect(CanopyFeatures.lockScreenPlayer.permission == nil)
        #expect(LockScreenPlayerSpace.isPrivateWindowServer)
        #expect(LockScreenPlayerSpace.collectsInput == false)
    }

    @Test func focusNameNeedsFullDiskAccessAndStartsOff() {
        #expect(CanopyFeatures.focusName.enabled == false)
        #expect(CanopyFeatures.focusName.permission == .fullDiskAccess)
        #expect(FocusNameReader.parse("Work") == "Work")
        #expect(FocusNameReader.parse("  ") == nil)
    }

    @Test func airPlayNamesNeedLocalNetworkAndStartOff() {
        #expect(CanopyFeatures.airPlayNames.enabled == false)
        #expect(CanopyFeatures.airPlayNames.permission == .localNetwork)
        #expect(CanopyFeatures.airPlayNames.usageStringKey == "NSLocalNetworkUsageDescription")
        #expect(AirPlayNames.bonjourTypes == ["_airplay._tcp", "_raop._tcp"])
        #expect(AirPlayNames.displayName(service: "Living Room", recordHexPrefix: "AABBCCDDEEFF@Living Room") == "Living Room")
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
        #expect(OutputDeviceIcon.symbol(for: .airPlay) == "airplayaudio")
    }

    @Test func wordsShareTheLineIntervalExactly() {
        let words = WordTiming.words("one two three", start: 1, end: 4)
        #expect(words.map(\.text) == ["one", "two", "three"])
        #expect(words.first?.start == 1)
        #expect(words.last?.end == 4)
        #expect(words[1].start == words[0].end)
    }
}
