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

    /// The set scripts guard exactly as the read script does: a press that queued behind a slow read must
    /// never launch a player that quit in the meantime.
    @Test func everySetScriptChecksRunningBeforeTheTell() throws {
        for player in players {
            var scripts = [MusicModeRules.setShuffleScript(player: player, on: true),
                           MusicModeRules.setShuffleScript(player: player, on: false)]
            for mode in RepeatMode.allCases {
                scripts.append(MusicModeRules.setRepeatScript(player: player, mode: mode))
            }
            for script in scripts {
                let notRunning = try #require(script.range(of: "is not running"))
                let tell = try #require(script.range(of: "tell application id"))
                #expect(notRunning.lowerBound < tell.lowerBound)
                #expect(script.hasPrefix("if application id \"\(player.bundleID)\" is not running then return \"\"\n"))
                #expect(script.hasSuffix("end tell"))
            }
        }
    }

    private func setScript(_ id: String, _ property: String, _ value: String) -> String {
        "if application id \"\(id)\" is not running then return \"\"\n"
            + "tell application id \"\(id)\"\n"
            + "set \(property) to \(value)\n"
            + "end tell"
    }

    @Test func shuffleScriptsCarryPropertyAndValue() {
        #expect(MusicModeRules.setShuffleScript(player: .music, on: true)
                == setScript("com.apple.Music", "shuffle enabled", "true"))
        #expect(MusicModeRules.setShuffleScript(player: .music, on: false)
                == setScript("com.apple.Music", "shuffle enabled", "false"))
        #expect(MusicModeRules.setShuffleScript(player: .spotify, on: true)
                == setScript("com.spotify.client", "shuffling", "true"))
        #expect(MusicModeRules.setShuffleScript(player: .spotify, on: false)
                == setScript("com.spotify.client", "shuffling", "false"))
    }

    @Test func repeatScriptsCarryPropertyAndValue() {
        #expect(MusicModeRules.setRepeatScript(player: .music, mode: .off)
                == setScript("com.apple.Music", "song repeat", "off"))
        #expect(MusicModeRules.setRepeatScript(player: .music, mode: .all)
                == setScript("com.apple.Music", "song repeat", "all"))
        #expect(MusicModeRules.setRepeatScript(player: .music, mode: .one)
                == setScript("com.apple.Music", "song repeat", "one"))
        #expect(MusicModeRules.setRepeatScript(player: .spotify, mode: .off)
                == setScript("com.spotify.client", "repeating", "false"))
        #expect(MusicModeRules.setRepeatScript(player: .spotify, mode: .all)
                == setScript("com.spotify.client", "repeating", "true"))
        // No repeat-one on Spotify: it turns repeating on.
        #expect(MusicModeRules.setRepeatScript(player: .spotify, mode: .one)
                == setScript("com.spotify.client", "repeating", "true"))
    }

    // MARK: When to read

    private func playing(_ player: NowPlaying.Player = .music, title: String = "Song", artist: String = "Band",
                         isPlaying: Bool = true) -> NowPlaying {
        NowPlaying(player: player, title: title, artist: artist, album: "Album", isPlaying: isPlaying,
                   duration: 200, position: 10)
    }

    private let known = MusicModes(shuffle: true, repeatMode: .all)

    @Test func aNewPlayerOrTrackReads() {
        #expect(MusicModeRules.shouldRead(previous: nil, current: playing(), modes: known))
        #expect(MusicModeRules.shouldRead(previous: playing(.music), current: playing(.spotify), modes: known))
        #expect(MusicModeRules.shouldRead(previous: playing(title: "A"), current: playing(title: "B"), modes: known))
        #expect(MusicModeRules.shouldRead(previous: playing(artist: "A"), current: playing(artist: "B"), modes: known))
    }

    @Test func playAndPauseOnAKnownTrackDoNotRead() {
        #expect(!MusicModeRules.shouldRead(previous: playing(isPlaying: true), current: playing(isPlaying: false), modes: known))
        #expect(!MusicModeRules.shouldRead(previous: playing(isPlaying: false), current: playing(isPlaying: true), modes: known))
    }

    @Test func unknownModesOnTheSameTrackRead() {
        // Automation was not confirmed yet when the track began, or has just been granted.
        #expect(MusicModeRules.shouldRead(previous: playing(), current: playing(), modes: MusicModes()))
        #expect(MusicModeRules.shouldRead(previous: playing(), current: playing(), modes: MusicModes(shuffle: true)))
        #expect(MusicModeRules.shouldRead(previous: playing(), current: playing(), modes: MusicModes(repeatMode: .off)))
    }

    // MARK: Reading an answer

    @Test func aReadAnswerReplacesTheModes() {
        let answer = "false\(sep)one"
        #expect(MusicModeRules.resolved(output: answer, player: .music, current: known, afterPress: false)
                == MusicModes(shuffle: false, repeatMode: .one))
        #expect(MusicModeRules.resolved(output: answer, player: .music, current: known, afterPress: true)
                == MusicModes(shuffle: false, repeatMode: .one))
    }

    @Test func anUnreadableAnswerLeavesTheModesUnknown() {
        for afterPress in [false, true] {
            #expect(MusicModeRules.resolved(output: "", player: .music, current: known, afterPress: afterPress) == MusicModes())
            #expect(MusicModeRules.resolved(output: "x", player: .spotify, current: known, afterPress: afterPress) == MusicModes())
        }
    }

    @Test func aFailedReadChangesNothingUnlessItFollowsAPress() {
        #expect(MusicModeRules.resolved(output: nil, player: .music, current: known, afterPress: false) == known)
        // After a press the control holds a guess the player never confirmed: it goes back to unknown.
        #expect(MusicModeRules.resolved(output: nil, player: .music, current: known, afterPress: true) == MusicModes())
    }

    // MARK: Spoken state

    @Test func spokenStateNamesUnknown() {
        #expect(MusicModeRules.spokenShuffle(true) == "on")
        #expect(MusicModeRules.spokenShuffle(false) == "off")
        #expect(MusicModeRules.spokenShuffle(nil) == "unknown")
        #expect(MusicModeRules.spokenRepeat(.off) == "off")
        #expect(MusicModeRules.spokenRepeat(.all) == "all")
        #expect(MusicModeRules.spokenRepeat(.one) == "one")
        #expect(MusicModeRules.spokenRepeat(nil) == "unknown")
    }
}
