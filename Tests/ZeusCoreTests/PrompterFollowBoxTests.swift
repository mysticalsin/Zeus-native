import Foundation
import Testing
@testable import ZeusCore

@Suite("Prompter follow box")
struct PrompterFollowBoxTests {
    private let sample = """
    # Intro
    Hi, I'm Tony. This is ZEUS, a lightning fast assistant.

    # Demo
    Watch the notch light up when the agent finishes its work.
    """

    private let markdown = """
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

    private let imported = """
    # Opening
    Welcome to ZEUS, see the site and code.

    First point

    Second point

    Numbered
    A quote

    # Close
    Thanks!
    """

    @Test func spokenWordsSkipCuesAndFoldMarks() {
        let blocks = [
            PrompterFollowBox.SpokenBlock(isCue: true, text: "Intro"),
            PrompterFollowBox.SpokenBlock(isCue: false, text: "Hi, I'm Tony."),
            PrompterFollowBox.SpokenBlock(isCue: true, text: ""),
            PrompterFollowBox.SpokenBlock(isCue: false, text: "Café naïve"),
        ]
        #expect(PrompterFollowBox.spokenWords(from: blocks) == ["hi", "im", "tony", "cafe", "naive"])
        #expect(PrompterFollowBox.normalize("It's 2 well-known") == ["its", "2", "well", "known"])
        #expect(PrompterFollowBox.normalize("I’m") == ["i", "m"])
        #expect(PrompterFollowBox.normalize("...") == [])
        #expect(PrompterFollowBox.normalize("") == [])
        #expect(ScriptFollower.normalize("Café") == ["cafe"])
    }

    @Test func anEmptyScriptIsFinishedAtTheStart() {
        #expect(PrompterFollowBox.progress(position: 0, count: 0) == 0)
        #expect(PrompterFollowBox.isFinished(position: 0, count: 0))
        #expect(PrompterFollowBox.reset(to: 4, count: 0) == 0)
        let step = PrompterFollowBox.hear(words: [], position: 0, lookahead: 40, minimumRun: 2, transcript: "hello")
        #expect(step == PrompterFollowBox.HearStep(position: 0, moved: false))
        let follower = ScriptFollower(words: [])
        #expect(follower.progress == 0)
        #expect(follower.isFinished)
    }

    @Test func resetClampsAndProgressSplitsTheScript() {
        #expect(PrompterFollowBox.reset(to: -3, count: 4) == 0)
        #expect(PrompterFollowBox.reset(to: 2, count: 4) == 2)
        #expect(PrompterFollowBox.reset(to: 99, count: 4) == 4)
        #expect(PrompterFollowBox.progress(position: 0, count: 4) == 0)
        #expect(PrompterFollowBox.progress(position: 2, count: 4) == 0.5)
        #expect(PrompterFollowBox.progress(position: 4, count: 4) == 1)
        #expect(!PrompterFollowBox.isFinished(position: 3, count: 4))
        #expect(PrompterFollowBox.isFinished(position: 4, count: 4))
    }

    @Test func aShortOrEmptyUtteranceDoesNotMove() {
        let words = ["hi", "there"]
        let one = PrompterFollowBox.hear(words: words, position: 0, lookahead: 40, minimumRun: 2, transcript: "hi")
        #expect(one == PrompterFollowBox.HearStep(position: 0, moved: false))
        let none = PrompterFollowBox.hear(words: words, position: 0, lookahead: 40, minimumRun: 2, transcript: "")
        #expect(none == PrompterFollowBox.HearStep(position: 0, moved: false))
        let done = PrompterFollowBox.hear(words: words, position: 2, lookahead: 40, minimumRun: 2, transcript: "hi there")
        #expect(done == PrompterFollowBox.HearStep(position: 2, moved: false))
    }

    @Test func twoWordsMoveAndAMinimumOfOneAcceptsASingleWord() {
        let words = ["hi", "there", "friend"]
        let pair = PrompterFollowBox.hear(words: words, position: 0, lookahead: 40, minimumRun: 2, transcript: "hi there")
        #expect(pair == PrompterFollowBox.HearStep(position: 2, moved: true))
        let single = PrompterFollowBox.hear(words: words, position: 0, lookahead: 1, minimumRun: 1, transcript: "hi")
        #expect(single == PrompterFollowBox.HearStep(position: 1, moved: true))
    }

    @Test func aTieKeepsTheEarlierMatch() {
        let words = ["a", "b", "a", "b"]
        let step = PrompterFollowBox.hear(words: words, position: 0, lookahead: 40, minimumRun: 2, transcript: "a b")
        #expect(step == PrompterFollowBox.HearStep(position: 2, moved: true))
    }

    @Test func aLongerRunBeatsAnEarlierShortOne() {
        let words = ["x", "b", "a", "b"]
        let step = PrompterFollowBox.hear(words: words, position: 0, lookahead: 40, minimumRun: 1, transcript: "a b")
        #expect(step == PrompterFollowBox.HearStep(position: 4, moved: true))
    }

    @Test func speechBehindThePositionDoesNotMove() {
        let words = ["a", "b", "c", "d", "e", "f"]
        let step = PrompterFollowBox.hear(words: words, position: 4, lookahead: 40, minimumRun: 2, transcript: "a b")
        #expect(step == PrompterFollowBox.HearStep(position: 4, moved: false))
    }

    @Test func aRunLongerThanTheTailOrANegativeLookaheadNeverMoves() {
        let words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        let long = PrompterFollowBox.hear(
            words: words,
            position: 0,
            lookahead: 40,
            minimumRun: 9,
            transcript: "one two three four five six seven eight nine"
        )
        #expect(long == PrompterFollowBox.HearStep(position: 0, moved: false))
        let behind = PrompterFollowBox.hear(words: words, position: 0, lookahead: -1, minimumRun: 2, transcript: "one two")
        #expect(behind == PrompterFollowBox.HearStep(position: 0, moved: false))
        let closed = PrompterFollowBox.hear(words: words, position: 0, lookahead: 0, minimumRun: 2, transcript: "one two")
        #expect(closed == PrompterFollowBox.HearStep(position: 0, moved: false))
    }

    @Test func keysPreferTheCodeAndThenTheCharacter() {
        #expect(PrompterFollowBox.command(keyCode: 49, characters: "m") == .toggle)
        #expect(PrompterFollowBox.command(keyCode: 53, characters: nil) == .stop)
        #expect(PrompterFollowBox.command(keyCode: 126, characters: nil) == .faster)
        #expect(PrompterFollowBox.command(keyCode: 125, characters: nil) == .slower)
        #expect(PrompterFollowBox.command(keyCode: 123, characters: nil) == .previousCue)
        #expect(PrompterFollowBox.command(keyCode: 124, characters: nil) == .nextCue)
        #expect(PrompterFollowBox.command(keyCode: 24, characters: "=") == .larger)
        #expect(PrompterFollowBox.command(keyCode: 24, characters: "+") == .larger)
        #expect(PrompterFollowBox.command(keyCode: 27, characters: "_") == .smaller)
        #expect(PrompterFollowBox.command(keyCode: 46, characters: "M") == .mirror)
        #expect(PrompterFollowBox.command(keyCode: 15, characters: "r") == .restart)
        #expect(PrompterFollowBox.command(keyCode: 0, characters: "a") == nil)
        #expect(PrompterFollowBox.command(keyCode: 0, characters: nil) == nil)
        #expect(PrompterKey.command(keyCode: 49, characters: " ") == .toggle)
    }

    @Test func markdownImportDropsFormattingAndKeepsCues() {
        #expect(PrompterFollowBox.importScript(from: markdown, isMarkdown: true) == imported)
        #expect(PrompterFollowBox.importScript(from: "a\r\nb", isMarkdown: false) == "a\nb")
        #expect(PrompterFollowBox.inline("say _hello_ there") == "say hello there")
        #expect(PrompterFollowBox.inline("a_b") == "a_b")
        #expect(PrompterFollowBox.inline("![logo](logo.png) **bold**") == "bold")
        #expect(PrompterFollowBox.importScript(from: "Keep\n<!-- secret -->\nNext", isMarkdown: true) == "Keep\n\nNext")
        #expect(PrompterFollowBox.importScript(from: "before\n```\nhidden\n```\nafter", isMarkdown: true) == "before\nafter")
        #expect(PrompterImport.script(from: markdown, isMarkdown: true) == imported)
        #expect(PrompterImport.isMarkdown(pathExtension: "MD"))
        #expect(PrompterImport.isMarkdown(pathExtension: "Markdown"))
        #expect(PrompterImport.isMarkdown(pathExtension: "mdown"))
        #expect(PrompterImport.isMarkdown(pathExtension: "mkd"))
        #expect(!PrompterImport.isMarkdown(pathExtension: "txt"))
        #expect(!PrompterFollowBox.isMarkdown(pathExtension: ""))
    }

    @Test func recordingNamesUseTheGivenZoneAndNumberCollisions() {
        let date = Date(timeIntervalSince1970: 1_793_475_612)
        let utc = TimeZone(identifier: "UTC")!
        let behind = TimeZone(secondsFromGMT: -3 * 60 * 60)!
        #expect(PrompterFollowBox.fileName(at: date, timeZone: utc) == "ZEUS Prompter 2026-10-31 at 19.40.12.mov")
        #expect(PrompterFollowBox.fileName(at: date, timeZone: behind) == "ZEUS Prompter 2026-10-31 at 16.40.12.mov")
        #expect(PrompterRecordingName.fileName(at: date, timeZone: utc) == "ZEUS Prompter 2026-10-31 at 19.40.12.mov")
        let folder = URL(fileURLWithPath: "/tmp/movies")
        var taken: Set<String> = []
        func claim(_ url: URL) -> URL {
            taken.insert(url.lastPathComponent)
            return url
        }
        let exists: (URL) -> Bool = { taken.contains($0.lastPathComponent) }
        let first = claim(PrompterFollowBox.recordingURL(folder: folder, at: date, timeZone: utc, exists: exists))
        let second = claim(PrompterFollowBox.recordingURL(folder: folder, at: date, timeZone: utc, exists: exists))
        let third = PrompterFollowBox.recordingURL(folder: folder, at: date, timeZone: utc, exists: exists)
        #expect(first.lastPathComponent == "ZEUS Prompter 2026-10-31 at 19.40.12.mov")
        #expect(second.lastPathComponent == "ZEUS Prompter 2026-10-31 at 19.40.12 2.mov")
        #expect(third.lastPathComponent == "ZEUS Prompter 2026-10-31 at 19.40.12 3.mov")
        #expect(PrompterRecordingName.url(in: folder, at: date, exists: { _ in false }).lastPathComponent == first.lastPathComponent)
    }

    @Test func modeTitlesAreTheShippedWords() {
        #expect(PrompterFollowBox.modeTitle(.words) == "Follow my words")
        #expect(PrompterFollowBox.modeTitle(.voice) == "Scroll while I speak")
        #expect(PrompterFollowBox.modeTitle(.steady) == "Steady speed")
        #expect(PrompterFollowMode.words.title == "Follow my words")
        #expect(PrompterFollowMode.voice.title == "Scroll while I speak")
        #expect(PrompterFollowMode.steady.title == "Steady speed")
        #expect(PrompterFollowMode.allCases.map(\.title) == ["Follow my words", "Scroll while I speak", "Steady speed"])
    }

    @Test func thePublicFollowerReadsTheBox() {
        let script = PrompterScript(sample)
        var follower = ScriptFollower(script: script)
        #expect(follower.words == PrompterFollowBox.spokenWords(from: script.blocks.map {
            PrompterFollowBox.SpokenBlock(isCue: $0.isCue, text: $0.text)
        }))
        #expect(follower.words.first == "hi")
        #expect(follower.words.contains("im"))
        #expect(!follower.words.contains("intro"))
        #expect(follower.words.count == 21)
        #expect(follower.lookahead == 40)
        #expect(follower.minimumRun == 2)
        let stayedOnOne = follower.hear("hi")
        #expect(!stayedOnOne)
        #expect(follower.position == 0)
        let movedToTony = follower.hear("hi I'm")
        #expect(movedToTony)
        #expect(follower.position == 2)
        let movedToZeus = follower.hear("Hi, I'm Tony. This is Zeus")
        #expect(movedToZeus)
        #expect(follower.position == 6)
        let adLib = follower.hear("Hi, I'm Tony. This is Zeus um let me see")
        #expect(!adLib)
        #expect(follower.position == 6)
        let alreadyThere = follower.hear("hi im tony this is zeus")
        #expect(!alreadyThere)
        #expect(follower.position == 6)
        var skipped = ScriptFollower(script: script)
        let reachedZeus = skipped.hear("hi im tony this is zeus")
        #expect(reachedZeus)
        let jumped = skipped.hear("watch the notch")
        #expect(jumped)
        #expect(skipped.position > 0 && skipped.words[skipped.position - 1] == "notch")
        var short = ScriptFollower(script: script)
        short.lookahead = 5
        let tooFar = short.hear("its work")
        #expect(!tooFar)
        #expect(short.position == 0)
        follower.reset(to: 15)
        let backward = follower.hear("hi im")
        #expect(!backward)
        #expect(follower.position == 15)
        let finished = follower.hear("finishes its work")
        #expect(finished)
        #expect(follower.isFinished)
        #expect(follower.progress == 1)
        follower.reset(to: 999)
        #expect(follower.position == follower.words.count)
        #expect(PrompterScript(PrompterImport.script(from: markdown, isMarkdown: true)).cues.map(\.text) == ["Opening", "Close"])
    }
}
