import Foundation
import Testing
@testable import ZeusCore

@Suite("Music modes box")
struct MusicModesBoxTests {
    private let music = MusicModesBox.Player.music
    private let spotify = MusicModesBox.Player.spotify
    private var sep: String { MusicModesBox.separator }

    @Test func theShippedPlayerFacts() {
        #expect(MusicModesBox.separator == "\u{1F}")
        #expect(MusicModesBox.separator.unicodeScalars.first?.value == 31)
        #expect(MusicModesBox.musicBundleID == "com.apple.Music")
        #expect(MusicModesBox.spotifyBundleID == "com.spotify.client")
        #expect(music.bundleID == MusicModesBox.musicBundleID)
        #expect(spotify.bundleID == MusicModesBox.spotifyBundleID)
        #expect(MusicModesBox.musicShuffleProperty == "shuffle enabled")
        #expect(MusicModesBox.musicRepeatProperty == "song repeat")
        #expect(MusicModesBox.spotifyShuffleProperty == "shuffling")
        #expect(MusicModesBox.spotifyRepeatProperty == "repeating")
    }

    @Test func musicSupportsOffAllAndOne() {
        #expect(MusicModesBox.supportedRepeatModes(music) == [.off, .all, .one])
    }

    @Test func spotifySupportsOffAndAll() {
        #expect(MusicModesBox.supportedRepeatModes(spotify) == [.off, .all])
        #expect(!MusicModesBox.supportedRepeatModes(spotify).contains(.one))
    }

    @Test func musicRepeatCycles() {
        #expect(MusicModesBox.nextRepeat(after: .off, player: music) == .all)
        #expect(MusicModesBox.nextRepeat(after: .all, player: music) == .one)
        #expect(MusicModesBox.nextRepeat(after: .one, player: music) == .off)
        #expect(MusicModesBox.nextRepeat(after: nil, player: music) == .all)
    }

    @Test func spotifyRepeatCyclesAndAForeignOneGoesOff() {
        #expect(MusicModesBox.nextRepeat(after: .off, player: spotify) == .all)
        #expect(MusicModesBox.nextRepeat(after: .all, player: spotify) == .off)
        #expect(MusicModesBox.nextRepeat(after: nil, player: spotify) == .all)
        #expect(MusicModesBox.nextRepeat(after: .one, player: spotify) == .off)
    }

    @Test func musicAnswersParse() {
        #expect(MusicModesBox.parse("true\(sep)all", player: music) == MusicModes(shuffle: true, repeatMode: .all))
        #expect(MusicModesBox.parse("false\(sep)off", player: music) == MusicModes(shuffle: false, repeatMode: .off))
        #expect(MusicModesBox.parse("true\(sep)one", player: music) == MusicModes(shuffle: true, repeatMode: .one))
    }

    @Test func spotifyAnswersParse() {
        #expect(MusicModesBox.parse("true\(sep)true", player: spotify) == MusicModes(shuffle: true, repeatMode: .all))
        #expect(MusicModesBox.parse("false\(sep)false", player: spotify) == MusicModes(shuffle: false, repeatMode: .off))
        #expect(MusicModesBox.parse("false\(sep)true", player: spotify) == MusicModes(shuffle: false, repeatMode: .all))
    }

    @Test func caseAndSurroundingSpaceAreIgnored() {
        #expect(MusicModesBox.parse(" TRUE\(sep)All\n", player: music) == MusicModes(shuffle: true, repeatMode: .all))
        #expect(MusicModesBox.parse("False\(sep)TRUE", player: spotify) == MusicModes(shuffle: false, repeatMode: .all))
        #expect(MusicModesBox.parse("true \(sep) all", player: music) == MusicModes(shuffle: true, repeatMode: .all))
    }

    @Test func emptyMalformedAndUnknownAnswersAreNil() {
        for player in [music, spotify] {
            #expect(MusicModesBox.parse(nil, player: player) == nil)
            #expect(MusicModesBox.parse("", player: player) == nil)
            #expect(MusicModesBox.parse("   \n", player: player) == nil)
            #expect(MusicModesBox.parse("true", player: player) == nil)
            #expect(MusicModesBox.parse("true\(sep)", player: player) == nil)
            #expect(MusicModesBox.parse("\(sep)true", player: player) == nil)
            #expect(MusicModesBox.parse("maybe\(sep)maybe", player: player) == nil)
            #expect(MusicModesBox.parse("true\(sep)true\(sep)true", player: player) == nil)
            #expect(MusicModesBox.parse("true\(sep)all\(sep)", player: player) == nil)
        }
        #expect(MusicModesBox.parse("true\(sep)all", player: spotify) == nil)
        #expect(MusicModesBox.parse("true\(sep)true", player: music) == nil)
        #expect(MusicModesBox.parse("true\(sep)sideways", player: music) == nil)
        #expect(MusicModesBox.parse("true\(sep)one", player: spotify) == nil)
        #expect(MusicModesBox.parse("yes\(sep)off", player: music) == nil)
    }

    @Test func readScriptsNameThePlayerAndCheckRunning() throws {
        let musicScript = MusicModesBox.readScript(player: music)
        let spotifyScript = MusicModesBox.readScript(player: spotify)
        #expect(musicScript == readScript(MusicModesBox.musicBundleID, "shuffle enabled", "song repeat"))
        #expect(spotifyScript == readScript(MusicModesBox.spotifyBundleID, "shuffling", "repeating"))
        for script in [musicScript, spotifyScript] {
            let notRunning = try #require(script.range(of: "is not running"))
            let tell = try #require(script.range(of: "tell application id"))
            #expect(notRunning.lowerBound < tell.lowerBound)
            #expect(script.contains("ASCII character 31"))
        }
        #expect(!musicScript.contains("shuffling"))
        #expect(!spotifyScript.contains("shuffle enabled"))
    }

    @Test func setScriptsCarryThePropertyAndValue() {
        #expect(MusicModesBox.setShuffleScript(player: music, on: true)
            == setScript(MusicModesBox.musicBundleID, "shuffle enabled", "true"))
        #expect(MusicModesBox.setShuffleScript(player: music, on: false)
            == setScript(MusicModesBox.musicBundleID, "shuffle enabled", "false"))
        #expect(MusicModesBox.setShuffleScript(player: spotify, on: true)
            == setScript(MusicModesBox.spotifyBundleID, "shuffling", "true"))
        #expect(MusicModesBox.setShuffleScript(player: spotify, on: false)
            == setScript(MusicModesBox.spotifyBundleID, "shuffling", "false"))
        #expect(MusicModesBox.setRepeatScript(player: music, mode: .off)
            == setScript(MusicModesBox.musicBundleID, "song repeat", "off"))
        #expect(MusicModesBox.setRepeatScript(player: music, mode: .all)
            == setScript(MusicModesBox.musicBundleID, "song repeat", "all"))
        #expect(MusicModesBox.setRepeatScript(player: music, mode: .one)
            == setScript(MusicModesBox.musicBundleID, "song repeat", "one"))
        #expect(MusicModesBox.setRepeatScript(player: spotify, mode: .off)
            == setScript(MusicModesBox.spotifyBundleID, "repeating", "false"))
        #expect(MusicModesBox.setRepeatScript(player: spotify, mode: .all)
            == setScript(MusicModesBox.spotifyBundleID, "repeating", "true"))
        #expect(MusicModesBox.setRepeatScript(player: spotify, mode: .one)
            == setScript(MusicModesBox.spotifyBundleID, "repeating", "true"))
    }

    @Test func aChangedTrackReadsAndAKnownTrackDoesNot() {
        #expect(MusicModesBox.shouldRead(hasPrevious: false, sameTrack: false, shuffle: true, repeatMode: .all))
        #expect(MusicModesBox.shouldRead(hasPrevious: false, sameTrack: true, shuffle: true, repeatMode: .all))
        #expect(MusicModesBox.shouldRead(hasPrevious: true, sameTrack: false, shuffle: true, repeatMode: .all))
        #expect(!MusicModesBox.shouldRead(hasPrevious: true, sameTrack: true, shuffle: true, repeatMode: .all))
        #expect(MusicModesBox.shouldRead(hasPrevious: true, sameTrack: true, shuffle: nil, repeatMode: .all))
        #expect(MusicModesBox.shouldRead(hasPrevious: true, sameTrack: true, shuffle: true, repeatMode: nil))
        #expect(MusicModesBox.shouldRead(hasPrevious: true, sameTrack: true, shuffle: nil, repeatMode: nil))
    }

    @Test func aReadAnswerReplacesOrClears() {
        let known = MusicModes(shuffle: true, repeatMode: .all)
        let answer = "false\(sep)one"
        #expect(MusicModesBox.resolved(output: answer, player: music, current: known, afterPress: false)
            == MusicModes(shuffle: false, repeatMode: .one))
        #expect(MusicModesBox.resolved(output: answer, player: music, current: known, afterPress: true)
            == MusicModes(shuffle: false, repeatMode: .one))
        #expect(MusicModesBox.resolved(output: nil, player: music, current: known, afterPress: false) == known)
        #expect(MusicModesBox.resolved(output: nil, player: music, current: known, afterPress: true) == MusicModes())
        #expect(MusicModesBox.resolved(output: "", player: music, current: known, afterPress: false) == MusicModes())
        #expect(MusicModesBox.resolved(output: "x", player: spotify, current: known, afterPress: true) == MusicModes())
    }

    @Test func spokenStateNamesUnknown() {
        #expect(MusicModesBox.spokenShuffle(true) == "on")
        #expect(MusicModesBox.spokenShuffle(false) == "off")
        #expect(MusicModesBox.spokenShuffle(nil) == "unknown")
        #expect(MusicModesBox.spokenRepeat(.off) == "off")
        #expect(MusicModesBox.spokenRepeat(.all) == "all")
        #expect(MusicModesBox.spokenRepeat(.one) == "one")
        #expect(MusicModesBox.spokenRepeat(nil) == "unknown")
    }

    @Test func thePublicRulesReadTheBox() {
        let known = MusicModes(shuffle: true, repeatMode: .all)
        let playing = NowPlaying(player: .music, title: "Song", artist: "Band", album: "Album",
                                 isPlaying: true, duration: 200, position: 10)
        let paused = NowPlaying(player: .music, title: "Song", artist: "Band", album: "Album",
                                isPlaying: false, duration: 200, position: 10)
        let other = NowPlaying(player: .spotify, title: "Song", artist: "Band", album: "Album",
                               isPlaying: true, duration: 200, position: 10)
        #expect(MusicModeRules.supportedRepeatModes(.music) == [.off, .all, .one])
        #expect(MusicModeRules.supportedRepeatModes(.spotify) == [.off, .all])
        #expect(MusicModeRules.nextRepeat(after: nil, player: .music) == .all)
        #expect(MusicModeRules.nextRepeat(after: .one, player: .spotify) == .off)
        #expect(MusicModeRules.parse("true\(NowPlaying.probeSeparator)all", player: .music)
            == MusicModes(shuffle: true, repeatMode: .all))
        #expect(MusicModeRules.parse(nil, player: .spotify) == nil)
        #expect(MusicModeRules.readScript(player: .music)
            == readScript("com.apple.Music", "shuffle enabled", "song repeat"))
        #expect(MusicModeRules.setShuffleScript(player: .spotify, on: false)
            == setScript("com.spotify.client", "shuffling", "false"))
        #expect(MusicModeRules.setRepeatScript(player: .spotify, mode: .one)
            == setScript("com.spotify.client", "repeating", "true"))
        #expect(MusicModeRules.spokenShuffle(nil) == "unknown")
        #expect(MusicModeRules.spokenRepeat(.one) == "one")
        #expect(MusicModeRules.resolved(output: nil, player: .music, current: known, afterPress: true) == MusicModes())
        #expect(MusicModeRules.resolved(output: "false\(NowPlaying.probeSeparator)off", player: .music, current: known, afterPress: false)
            == MusicModes(shuffle: false, repeatMode: .off))
        #expect(MusicModeRules.shouldRead(previous: nil, current: playing, modes: known))
        #expect(MusicModeRules.shouldRead(previous: playing, current: other, modes: known))
        #expect(!MusicModeRules.shouldRead(previous: playing, current: paused, modes: known))
        #expect(MusicModeRules.shouldRead(previous: playing, current: paused, modes: MusicModes()))
    }

    private func readScript(_ id: String, _ shuffle: String, _ repeating: String) -> String {
        "if application id \"\(id)\" is not running then return \"\"\n"
            + "tell application id \"\(id)\"\n"
            + "set sep to (ASCII character 31)\n"
            + "return (\(shuffle) as string) & sep & (\(repeating) as string)\n"
            + "end tell"
    }

    private func setScript(_ id: String, _ property: String, _ value: String) -> String {
        "if application id \"\(id)\" is not running then return \"\"\n"
            + "tell application id \"\(id)\"\n"
            + "set \(property) to \(value)\n"
            + "end tell"
    }
}
