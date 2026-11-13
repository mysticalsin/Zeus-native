import Foundation
import Testing
@testable import ZeusCore

@Suite("Music shuffle and repeat modes") struct MusicModesTests {
    private let sep = NowPlaying.probeSeparator
    private let players: [NowPlaying.Player] = [.music, .spotify]

    // MARK: Parsing

    @Test func musicAnswersParse() {
        #expect(MusicModeRules.parse("true\(sep)all", player: .music) == MusicModes(shuffle: true, repeatMode: .all))
        #expect(MusicModeRules.parse("false\(sep)off", player: .music) == MusicModes(shuffle: false, repeatMode: .off))
        #expect(MusicModeRules.parse("true\(sep)one", player: .music) == MusicModes(shuffle: true, repeatMode: .one))
    }

    @Test func spotifyAnswersParse() {
        #expect(MusicModeRules.parse("true\(sep)true", player: .spotify) == MusicModes(shuffle: true, repeatMode: .all))
        #expect(MusicModeRules.parse("false\(sep)false", player: .spotify) == MusicModes(shuffle: false, repeatMode: .off))
        #expect(MusicModeRules.parse("false\(sep)true", player: .spotify) == MusicModes(shuffle: false, repeatMode: .all))
    }

    @Test func caseAndSurroundingSpaceAreIgnored() {
        #expect(MusicModeRules.parse(" TRUE\(sep)All\n", player: .music) == MusicModes(shuffle: true, repeatMode: .all))
        #expect(MusicModeRules.parse("False\(sep)TRUE", player: .spotify) == MusicModes(shuffle: false, repeatMode: .all))
    }

    @Test func emptyMalformedAndUnknownAnswersAreNil() {
        for player in players {
            #expect(MusicModeRules.parse(nil, player: player) == nil)
            #expect(MusicModeRules.parse("", player: player) == nil)
            #expect(MusicModeRules.parse("true", player: player) == nil)
            #expect(MusicModeRules.parse("true\(sep)", player: player) == nil)
            #expect(MusicModeRules.parse("\(sep)true", player: player) == nil)
            #expect(MusicModeRules.parse("maybe\(sep)maybe", player: player) == nil)
            #expect(MusicModeRules.parse("true\(sep)true\(sep)true", player: player) == nil)
        }
        // Each player only understands its own words.
        #expect(MusicModeRules.parse("true\(sep)all", player: .spotify) == nil)
        #expect(MusicModeRules.parse("true\(sep)true", player: .music) == nil)
        #expect(MusicModeRules.parse("true\(sep)sideways", player: .music) == nil)
    }

    @Test func unknownModesStartEmpty() {
        let modes = MusicModes()
        #expect(modes.shuffle == nil)
        #expect(modes.repeatMode == nil)
    }

    // MARK: Repeat cycle

    @Test func supportedRepeatModes() {
        #expect(MusicModeRules.supportedRepeatModes(.music) == [.off, .all, .one])
        #expect(MusicModeRules.supportedRepeatModes(.spotify) == [.off, .all])
    }

    @Test func musicRepeatCycles() {
        #expect(MusicModeRules.nextRepeat(after: .off, player: .music) == .all)
        #expect(MusicModeRules.nextRepeat(after: .all, player: .music) == .one)
        #expect(MusicModeRules.nextRepeat(after: .one, player: .music) == .off)
        #expect(MusicModeRules.nextRepeat(after: nil, player: .music) == .all)
    }

    @Test func spotifyRepeatCycles() {
        #expect(MusicModeRules.nextRepeat(after: .off, player: .spotify) == .all)
        #expect(MusicModeRules.nextRepeat(after: .all, player: .spotify) == .off)
        #expect(MusicModeRules.nextRepeat(after: nil, player: .spotify) == .all)
        // Spotify has no repeat-one: a stale or foreign value goes back to off.
        #expect(MusicModeRules.nextRepeat(after: .one, player: .spotify) == .off)
    }

    // MARK: Scripts

    @Test func everyScriptNamesThePlayerByBundleID() {
        for player in players {
            let id = "application id \"\(player.bundleID)\""
            #expect(MusicModeRules.readScript(player: player).contains(id))
            #expect(MusicModeRules.setShuffleScript(player: player, on: true).contains(id))
            #expect(MusicModeRules.setShuffleScript(player: player, on: false).contains(id))
            for mode in RepeatMode.allCases {
                #expect(MusicModeRules.setRepeatScript(player: player, mode: mode).contains(id))
            }
        }
    }

    @Test func readScriptChecksRunningBeforeTheTell() throws {
        for player in players {
            let script = MusicModeRules.readScript(player: player)
            let notRunning = try #require(script.range(of: "is not running"))
            let tell = try #require(script.range(of: "tell application id"))
            #expect(notRunning.lowerBound < tell.lowerBound)
            #expect(script.hasPrefix("if application id \"\(player.bundleID)\" is not running then return \"\""))
        }
    }

    @Test func readScriptAsksForTheRightProperties() {
        let music = MusicModeRules.readScript(player: .music)
        #expect(music.contains("shuffle enabled"))
        #expect(music.contains("song repeat"))
        #expect(music.contains("ASCII character 31"))
        let spotify = MusicModeRules.readScript(player: .spotify)
        #expect(spotify.contains("shuffling"))
        #expect(spotify.contains("repeating"))
        #expect(spotify.contains("ASCII character 31"))
        #expect(NowPlaying.probeSeparator == "\u{1F}")
    }

    @Test func shuffleScriptsCarryPropertyAndValue() {
        #expect(MusicModeRules.setShuffleScript(player: .music, on: true)
                == "tell application id \"com.apple.Music\" to set shuffle enabled to true")
        #expect(MusicModeRules.setShuffleScript(player: .music, on: false)
                == "tell application id \"com.apple.Music\" to set shuffle enabled to false")
        #expect(MusicModeRules.setShuffleScript(player: .spotify, on: true)
                == "tell application id \"com.spotify.client\" to set shuffling to true")
        #expect(MusicModeRules.setShuffleScript(player: .spotify, on: false)
                == "tell application id \"com.spotify.client\" to set shuffling to false")
    }

    @Test func repeatScriptsCarryPropertyAndValue() {
        #expect(MusicModeRules.setRepeatScript(player: .music, mode: .off)
                == "tell application id \"com.apple.Music\" to set song repeat to off")
        #expect(MusicModeRules.setRepeatScript(player: .music, mode: .all)
                == "tell application id \"com.apple.Music\" to set song repeat to all")
        #expect(MusicModeRules.setRepeatScript(player: .music, mode: .one)
                == "tell application id \"com.apple.Music\" to set song repeat to one")
        #expect(MusicModeRules.setRepeatScript(player: .spotify, mode: .off)
                == "tell application id \"com.spotify.client\" to set repeating to false")
        #expect(MusicModeRules.setRepeatScript(player: .spotify, mode: .all)
                == "tell application id \"com.spotify.client\" to set repeating to true")
        // No repeat-one on Spotify: it turns repeating on.
        #expect(MusicModeRules.setRepeatScript(player: .spotify, mode: .one)
                == "tell application id \"com.spotify.client\" to set repeating to true")
    }
}
