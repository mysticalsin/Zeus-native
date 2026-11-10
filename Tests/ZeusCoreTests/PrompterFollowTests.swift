import Foundation
import Testing
@testable import ZeusCore

@Suite("Prompter follow")
struct PrompterFollowTests {
    let script = PrompterScript("""
    # Intro
    Hi, I'm Tony. This is ZEUS, a lightning fast assistant.

    # Demo
    Watch the notch light up when the agent finishes its work.
    """)

    @Test func wordsSkipCues() {
        let follower = ScriptFollower(script: script)
        #expect(follower.words.first == "hi")
        #expect(follower.words.contains("im"))
        #expect(!follower.words.contains("intro"))
        #expect(follower.words.count == 21)
    }

    @Test func followsPartialTranscripts() {
        var follower = ScriptFollower(script: script)
        let moved1 = follower.hear("hi")
        #expect(!moved1)
        let moved2 = follower.hear("hi I'm")
        #expect(moved2)
        #expect(follower.position == 2)
        let moved3 = follower.hear("Hi, I'm Tony. This is Zeus")
        #expect(moved3)
        #expect(follower.position == 6)
        // Ad-libbing does not move it.
        let moved4 = follower.hear("Hi, I'm Tony. This is Zeus um let me see")
        #expect(!moved4)
        #expect(follower.position == 6)
    }

    @Test func toleratesSkippedWordsButNotFarJumps() {
        var follower = ScriptFollower(script: script)
        follower.hear("hi im tony this is zeus")
        // Skips "a lightning fast assistant" and carries on.
        let moved5 = follower.hear("watch the notch")
        #expect(moved5)
        #expect(follower.words[follower.position - 1] == "notch")
        var short = ScriptFollower(script: script)
        short.lookahead = 5
        let moved6 = short.hear("its work")
        #expect(!moved6)
        #expect(short.position == 0)
    }

    @Test func neverGoesBackAndFinishes() {
        var follower = ScriptFollower(script: script)
        follower.reset(to: 15)
        let moved7 = follower.hear("hi im")
        #expect(!moved7)
        #expect(follower.position == 15)
        let moved8 = follower.hear("finishes its work")
        #expect(moved8)
        #expect(follower.isFinished)
        #expect(follower.progress == 1)
        follower.reset(to: 999)
        #expect(follower.position == follower.words.count)
    }

    @Test func keys() {
        #expect(PrompterKey.command(keyCode: 49, characters: " ") == .toggle)
        #expect(PrompterKey.command(keyCode: 53, characters: nil) == .stop)
        #expect(PrompterKey.command(keyCode: 126, characters: nil) == .faster)
        #expect(PrompterKey.command(keyCode: 125, characters: nil) == .slower)
        #expect(PrompterKey.command(keyCode: 123, characters: nil) == .previousCue)
        #expect(PrompterKey.command(keyCode: 124, characters: nil) == .nextCue)
        #expect(PrompterKey.command(keyCode: 24, characters: "=") == .larger)
        #expect(PrompterKey.command(keyCode: 27, characters: "-") == .smaller)
        #expect(PrompterKey.command(keyCode: 46, characters: "M") == .mirror)
        #expect(PrompterKey.command(keyCode: 15, characters: "r") == .restart)
        #expect(PrompterKey.command(keyCode: 0, characters: "a") == nil)
    }

    @Test func markdownImport() {
        let markdown = """
        # Opening
        Welcome to **ZEUS**, see [the site](https://example.com) and `code`.
        ![logo](logo.png)

        - First point
        - Second _point_
        1. Numbered
        > A quote
        ```
        let hidden = true
        ```
        ---
        ## Close
        Thanks!
        """
        let script = PrompterImport.script(from: markdown, isMarkdown: true)
        #expect(script == """
        # Opening
        Welcome to ZEUS, see the site and code.

        First point

        Second point

        Numbered
        A quote

        # Close
        Thanks!
        """)
        #expect(PrompterScript(script).cues.map(\.text) == ["Opening", "Close"])
        #expect(PrompterImport.script(from: "a\r\nb", isMarkdown: false) == "a\nb")
        #expect(PrompterImport.isMarkdown(pathExtension: "MD"))
        #expect(!PrompterImport.isMarkdown(pathExtension: "txt"))
    }

    @Test func recordingNames() {
        let date = Date(timeIntervalSince1970: 1_793_475_612) // 2026-10-31 19:40:12 UTC
        let utc = TimeZone(identifier: "UTC")!
        #expect(PrompterRecordingName.fileName(at: date, timeZone: utc) == "ZEUS Prompter 2026-10-31 at 19.40.12.mov")
        var taken: Set<String> = []
        let folder = URL(fileURLWithPath: "/tmp/movies")
        let first = PrompterRecordingName.url(in: folder, at: date) { taken.contains($0.lastPathComponent) }
        taken.insert(first.lastPathComponent)
        let second = PrompterRecordingName.url(in: folder, at: date) { taken.contains($0.lastPathComponent) }
        #expect(second.lastPathComponent.hasSuffix(" 2.mov"))
    }
}
