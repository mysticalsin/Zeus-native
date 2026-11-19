import Foundation
import Testing
@testable import ZeusCore

/// A DRAW tag is never speech, wherever it sits and however it ends.
@Suite struct ZeusTagDrawLeakTests {
    private static let json = #"{"s":1,"m":[{"k":"ring","x":412,"y":88,"r":24,"at":0}]}"#

    private struct Run { var tags: [ZeusTag] = []; var spoken = ""; var afterFeed = "" }

    /// Feeds the chunks, notes what was already spoken before the stream ended, then finishes.
    private static func run(_ chunks: [String]) -> Run {
        var parser = ZeusTagStreamParser()
        var run = Run()
        func take(_ outputs: [ZeusTagStreamParser.Output]) {
            for output in outputs {
                switch output {
                case .tag(let tag): run.tags.append(tag)
                case .text(let text): run.spoken += text
                }
            }
        }
        for chunk in chunks { take(parser.feed(chunk)) }
        run.afterFeed = run.spoken
        take(parser.finish())
        return run
    }

    private static func characters(_ text: String) -> [String] { text.map(String.init) }

    private func expectSilent(_ spoken: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(!spoken.contains("DRAW") && !spoken.contains("{") && !spoken.contains("\"k\""),
                "spoken: \(spoken)", sourceLocation: sourceLocation)
    }

    @Test func aTagAfterSpokenWordsIsNeverSpoken() {
        for chunks in [["Sure. [DRAW:\(Self.json)] Open the File menu."], Self.characters("Sure. [DRAW:\(Self.json)] Open the File menu.")] {
            let run = Self.run(chunks)
            expectSilent(run.spoken)
            #expect(run.spoken.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces) == "Sure. Open the File menu.")
        }
    }

    @Test func aTagAtTheEndOfTheReplyIsNeverSpoken() {
        let run = Self.run(["Sure. [DRAW:\(Self.json)]"])
        expectSilent(run.spoken)
        #expect(run.spoken.trimmingCharacters(in: .whitespaces) == "Sure.")
    }

    @Test func aTagWithNoClosingBracketIsNeverSpokenAndTheSpeechFollows() {
        // Leading: the JSON is complete, so it still counts as the tag; the words after it are speech.
        let leading = Self.run(["[DRAW:\(Self.json) Open the File menu."])
        expectSilent(leading.spoken)
        #expect(leading.spoken.trimmingCharacters(in: .whitespaces) == "Open the File menu.")
        #expect(leading.tags.count == 1)
        // Mid-reply: dropped, the speech around it is kept.
        let middle = Self.run(["Sure. [DRAW:\(Self.json) Open the File menu."])
        expectSilent(middle.spoken)
        #expect(middle.spoken.contains("Sure.") && middle.spoken.contains("Open the File menu."))
        // Split into single characters, the same.
        let split = Self.run(Self.characters("[DRAW:\(Self.json) Open the File menu."))
        expectSilent(split.spoken)
        #expect(split.spoken.trimmingCharacters(in: .whitespaces) == "Open the File menu.")
    }

    @Test func unbalancedBracesEndAtTheLineBreakAndTheSpeechStartsBeforeTheStreamEnds() {
        let bad = #"[DRAW:{"s":1,"m":[{"k":"ring","x":4"#
        for chunks in [[bad + "\nOpen the File menu. "], Self.characters(bad + "\nOpen the File menu. ")] {
            let run = Self.run(chunks)
            expectSilent(run.afterFeed)
            #expect(run.afterFeed.contains("Open the File menu."), "spoken before the stream ended: \(run.afterFeed)")
            #expect(run.tags.isEmpty)
        }
    }

    @Test func anUnterminatedTagIsDroppedAtTheSizeBoundAndAtTheEndOfTheStream() {
        let endless = #"[DRAW:{"s":1,"m":["# + String(repeating: #"{"k":"ring"},"#, count: 700)
        let run = Self.run([endless, endless, "\nThen it speaks."])
        expectSilent(run.spoken)
        #expect(run.afterFeed.contains("Then it speaks."))
        let shortEnd = Self.run([#"Hello. [DRAW:{"s":1,"m":[{"k":"ring""#])
        expectSilent(shortEnd.spoken)
        #expect(shortEnd.spoken.trimmingCharacters(in: .whitespaces) == "Hello.")
    }

    @Test func bracesAndBracketsInsideStringsDoNotEndTheTag() {
        let tricky = #"{"s":1,"m":[{"k":"card","x":1,"y":2,"t":"a } ] [DRAW: b","at":0}]}"#
        let run = Self.run(["Sure. [DRAW:\(tricky)] Done."])
        expectSilent(run.spoken)
        #expect(run.spoken.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces) == "Sure. Done.")
    }

    @Test func theWholeReplyParserAndTheSanitizerAlsoStripEveryShape() {
        for text in ["Sure. [DRAW:\(Self.json)] Go.", "Sure. [DRAW:\(Self.json) Go.", #"Sure. [DRAW:{"m":[{"k":"ri"#] {
            let parsed = ZeusTagParser.parse(text)
            expectSilent(parsed.spokenText)
            let cleaned = ResponseSanitizer.stripArtifacts(text)
            expectSilent(cleaned)
            #expect(cleaned.hasPrefix("Sure."))
        }
        #expect(ResponseSanitizer.sanitize("Hi [DRAW:\(Self.json)] there").contains("there"))
    }
}
