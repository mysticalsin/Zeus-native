import Foundation
import Testing
@testable import ZeusCore

@Suite("Media island features")
struct MediaIslandFeatureTests {
    @Test func theSystemReaderIsBoundedAndLosesToAPlayingPlayer() {
        #expect(SystemNowPlayingLaunch.settingID == "music.systemNowPlaying")
        #expect(SystemNowPlayingLaunch.timeout == 2)
        #expect(SystemNowPlayingLaunch.maxOutputBytes == 4096)
        #expect(SystemNowPlayingLaunch.executable == "/usr/bin/perl")
        var arbiter = NowPlayingArbiter()
        let now = Date(timeIntervalSince1970: 10)
        let player = NowPlaying(source: .player(.music), title: "Live", artist: "Band", album: "", isPlaying: true,
                                duration: 100, position: 1, positionAt: now)
        let system = NowPlaying(source: .system, title: "Helper", artist: "", album: "", isPlaying: true,
                                duration: 100, position: 1, positionAt: now)
        #expect(arbiter.update(.system, system, now: now))
        #expect(arbiter.update(.player(.music), player, now: now.addingTimeInterval(1)))
        #expect(arbiter.shown(follow: .any)?.playing.source == .player(.music))
    }

    @Test func systemNowPlayingIsOffUntilAskedAndParsesThePerlLine() {
        #expect(MediaIslandFeatures.systemNowPlaying.enabled == false)
        #expect(MediaIslandFeatures.systemNowPlaying.permission == nil)
        #expect(SystemNowPlayingAdapter.command.last == "now-playing.pl")
        let line = SystemNowPlayingAdapter.parse("Night Drive\tAda\tCoast\t1\t12.5\t180\n")
        #expect(line == SystemNowPlayingLine(title: "Night Drive", artist: "Ada", album: "Coast", playing: true, position: 12.5, duration: 180))
        #expect(SystemNowPlayingAdapter.parse("nope") == nil)
    }

    @Test func aConnectedAudioDeviceShowsItsBatteryUntilTheOverlayTimesOut() {
        #expect(EarbudOverlayRule.settingID == "music.earbudOverlay")
        #expect(EarbudOverlayRule.visibleFor == 8)
        let reading = EarbudOverlayRule.reading(name: " Buds ", audio: true, connected: true, left: 80, right: 101, casePercent: -1)
        #expect(reading == EarbudReading(name: "Buds", left: 80, right: nil, casePercent: nil))
        #expect(EarbudOverlayRule.reading(name: "Buds", audio: true, connected: false, left: 1, right: 1, casePercent: 1) == nil)
        #expect(EarbudOverlayRule.reading(name: "Speaker", audio: false, connected: true, left: nil, right: nil, casePercent: nil) == nil)
        let shownAt = Date(timeIntervalSince1970: 10)
        #expect(EarbudOverlayRule.visible(reading: reading, enabled: true, now: shownAt.addingTimeInterval(7), shownAt: shownAt))
        #expect(!EarbudOverlayRule.visible(reading: reading, enabled: true, now: shownAt.addingTimeInterval(8), shownAt: shownAt))
        #expect(!EarbudOverlayRule.visible(reading: reading, enabled: false, now: shownAt, shownAt: shownAt))
    }

    @Test func theEarbudOverlayNeedsBluetoothAndStartsOff() {
        #expect(MediaIslandFeatures.earbudOverlay.enabled == false)
        #expect(MediaIslandFeatures.earbudOverlay.permission == .bluetooth)
        #expect(MediaIslandFeatures.earbudOverlay.usageStringKey == "NSBluetoothAlwaysUsageDescription")
    }

    @Test func theLockScreenPlayerFailsClosedWithoutAPrivateSpace() {
        #expect(LockScreenPlayerGate.settingID == "music.lockScreenPlayer")
        #expect(LockScreenPlayerGate.result(enabled: false, spaceAvailable: true, inputIgnored: true) == .off)
        #expect(LockScreenPlayerGate.result(enabled: true, spaceAvailable: false, inputIgnored: false) == .unavailable)
        #expect(LockScreenPlayerGate.result(enabled: true, spaceAvailable: true, inputIgnored: false) == .unavailable)
        #expect(LockScreenPlayerGate.result(enabled: true, spaceAvailable: true, inputIgnored: true) == .shown)
    }

    @Test func theLockScreenPlayerUsesAPrivateSpaceAndAsksForNothing() {
        #expect(MediaIslandFeatures.lockScreenPlayer.enabled == false)
        #expect(MediaIslandFeatures.lockScreenPlayer.permission == nil)
        #expect(LockScreenPlayerSpace.isPrivateWindowServer)
        #expect(LockScreenPlayerSpace.collectsInput == false)
    }

    @Test func theActiveFocusNameComesFromTheStoreOrNeedsAccess() {
        let configurations = Data(#"{"data":[{"modeIdentifier":"com.apple.focus.work","mode":{"name":"Work"}}]}"#.utf8)
        let assertions = Data(#"{"data":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}}]}"#.utf8)
        let files = FocusNameStore.Files(configurations: configurations, assertions: assertions, permissionDenied: false)
        #expect(FocusNameStore.settingID == "music.focusName")
        #expect(FocusNameStore.status(enabled: false, files: files) == .off)
        #expect(FocusNameStore.status(enabled: true, files: files) == .named("Work"))
        #expect(FocusNameStore.status(enabled: true, files: FocusNameStore.Files(configurations: nil, assertions: nil, permissionDenied: true)) == .needsFullDiskAccess)
        #expect(FocusNameStore.status(enabled: true, files: FocusNameStore.Files(configurations: configurations, assertions: Data("{}".utf8), permissionDenied: false)) == .unavailable)
    }

    @Test func focusNameNeedsFullDiskAccessAndStartsOff() {
        #expect(MediaIslandFeatures.focusName.enabled == false)
        #expect(MediaIslandFeatures.focusName.permission == .fullDiskAccess)
        #expect(FocusNameReader.parse("Work") == "Work")
        #expect(FocusNameReader.parse("  ") == nil)
    }

    @Test func bothReceiverServiceTypesBecomeMenuNames() {
        #expect(ReceiverCatalog.settingID == "music.receiverNames")
        let names = ReceiverCatalog.names([
            ReceiverService(name: "Kitchen", type: "_airplay._tcp"),
            ReceiverService(name: "AABBCC@Bedroom", type: "_raop._tcp"),
            ReceiverService(name: "Kitchen", type: "_raop._tcp"),
            ReceiverService(name: "Other", type: "_http._tcp"),
        ])
        #expect(names == ["Kitchen", "Bedroom"])
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
        #expect(PlaybackCollapse.settingID == "music.collapseOnPause")
        #expect(PlaybackCollapse.collapsed(paused: true, enabled: true))
        #expect(!PlaybackCollapse.collapsed(paused: false, enabled: true))
        #expect(!PlaybackCollapse.collapsed(isPlaying: nil, settingOn: true))
        #expect(!PlaybackCollapse.animates(reduceMotion: true))
        #expect(PlaybackCollapse.animates(reduceMotion: false))
        #expect(!PlaybackCollapse.collapsed(paused: true, enabled: false))
        #expect(OutputDeviceIcon.symbol(for: .speakers) == "speaker.wave.2.fill")
        #expect(OutputDeviceIcon.symbol(for: .headphones) == "headphones")
        #expect(OutputDeviceIcon.symbol(for: .receiver) == "airplayaudio")
        #expect(OutputDeviceIcon.kind(transport: 0x626C7565) == .headphones)
        #expect(OutputDeviceIcon.kind(transport: 0x626C6561) == .headphones)
        #expect(OutputDeviceIcon.kind(transport: 0x61697270) == .receiver)
        #expect(OutputDeviceIcon.kind(transport: 0x626C746E) == .speakers)
    }

    @Test func aLineWithWordTimesUsesThemAndAPlainLineUsesEqualSlices() {
        let timed = LyricLine(time: 1, text: "one two", wordStamps: [
            LyricWord(text: "one ", start: 1, end: 1.4),
            LyricWord(text: "two", start: 1.4, end: 1.4),
        ])
        let kept = LyricWordTiming.displayWords(in: timed, lineEnd: 2)
        #expect(kept.map(\.start) == [1, 1.4])
        #expect(kept.last?.end == 2)
        let plain = LyricWordTiming.displayWords(in: LyricLine(time: 0, text: "one two three"), lineEnd: 3)
        #expect(plain.map(\.start) == [0, 1, 2])
        #expect(plain.last?.end == 3)
        #expect(plain[1].start == plain[0].end)
    }

    @Test func wordsShareTheLineIntervalExactly() {
        let words = WordTiming.words("one two three", start: 1, end: 4)
        #expect(words.map(\.text) == ["one", "two", "three"])
        #expect(words.first?.start == 1)
        #expect(words.last?.end == 4)
        #expect(words[1].start == words[0].end)
    }
}
