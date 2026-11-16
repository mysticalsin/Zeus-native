import Foundation
import Testing
@testable import ZeusCore

@Suite("Ultron speech text, sight fallback and filler gate")
struct UltronTakeCCoreTests {
    @Test func anAsciiEllipsisBeforeALowercaseWordBecomesAComma() {
        #expect(UltronSpeechText.sanitize("Fine... that works.") == "Fine, that works.")
        #expect(UltronSpeechText.sanitize("Fine ... that works.") == "Fine, that works.")
    }

    @Test func anEllipsisAtASentenceEndBecomesAPeriod() {
        #expect(UltronSpeechText.sanitize("Done...") == "Done.")
        #expect(UltronSpeechText.sanitize("Done... Next up.") == "Done. Next up.")
    }

    @Test func theUnicodeEllipsisAndLongerRunsAreHandledTheSame() {
        #expect(UltronSpeechText.sanitize("Done… that works.") == "Done, that works.")
        #expect(UltronSpeechText.sanitize("Done…") == "Done.")
        #expect(UltronSpeechText.sanitize("Wait.... then go.") == "Wait, then go.")
    }

    @Test func noEllipsisSurvivesAndPlainTextIsUntouched() {
        let messy = "One... two… three...... four."
        let clean = UltronSpeechText.sanitize(messy)
        #expect(!clean.contains("...") && !clean.contains("\u{2026}"))
        #expect(UltronSpeechText.sanitize("A short clause, then another.") == "A short clause, then another.")
        #expect(UltronSpeechText.sanitize("") == "")
    }

    @Test func onlyTheUltronPersonalityIsSanitizedForTheVoice() {
        #expect(UltronSpeechText.prepared("Hm... fine.", personality: .ultron) == "Hm, fine.")
        #expect(UltronSpeechText.prepared("Hm... fine.", personality: .plain) == "Hm... fine.")
    }

    @Test func theImageEngineFailureHasItsOwnDistinctWording() {
        let failed = ScreenSightNote.line(labels: [], reason: .imageEngineFailed)
        let blocked = ScreenSightNote.line(labels: [], reason: .imagesBlocked)
        #expect(failed != blocked)
        #expect(failed.contains("cannot see the screen"))
        #expect(failed.contains("[POINT:none]"))
        #expect(failed.lowercased().contains("image"))
    }

    @Test func theTextFallbackNeedsNoWordsAndNoActionOnTheImageRace() {
        #expect(TalkSightPolicy.fallbackAllowed(spokeAnything: false, actionStarted: false))
        #expect(!TalkSightPolicy.fallbackAllowed(spokeAnything: true, actionStarted: false))
        #expect(!TalkSightPolicy.fallbackAllowed(spokeAnything: false, actionStarted: true))
        #expect(!TalkSightPolicy.fallbackAllowed(spokeAnything: true, actionStarted: true))
    }

    @Test func theFillerGateLetsExactlyOneLineThroughPerTurn() {
        var gate = TurnFillerGate()
        let first = gate.take()
        let second = gate.take()
        let third = gate.take()
        #expect(first)
        #expect(!second)
        #expect(!third)
        var next = TurnFillerGate()
        let fresh = next.take()
        #expect(fresh, "a new turn gets a new gate")
    }

    @Test func anEllipsisBeforeAnythingButAWordLeavesNoMark() {
        #expect(UltronSpeechText.sanitize("Hmm...?") == "Hmm?")
        #expect(UltronSpeechText.sanitize("He said \"wait...\" and left.") == "He said \"wait\" and left.")
        #expect(UltronSpeechText.sanitize("Really...! Fine.") == "Really! Fine.")
    }

    @Test func numberRangesCodeLikeTokensAndBracketedElisionsAreLeftAlone() {
        #expect(UltronSpeechText.sanitize("Pages 1...5 now.") == "Pages 1...5 now.")
        #expect(UltronSpeechText.sanitize("Use a...b here.") == "Use a...b here.")
        #expect(UltronSpeechText.sanitize("The [...] part.") == "The [...] part.")
    }

    @Test func wordsJoinedByATightEllipsisBecomeACommaPause() {
        #expect(UltronSpeechText.sanitize("Well...yes, that works.") == "Well, yes, that works.")
        #expect(UltronSpeechText.sanitize("Hmm...okay.") == "Hmm, okay.")
        #expect(UltronSpeechText.sanitize("Wait\u{2026}Now we see.") == "Wait. Now we see.")
    }

    @Test func anEllipsisBeforeALowercaseWordStaysInOneStreamedSentence() {
        var splitter = SentenceSplitter()
        #expect(splitter.feed("Fine... that works. ") == ["Fine... that works."])
        var unicode = SentenceSplitter()
        #expect(unicode.feed("Fine\u{2026} that works. ") == ["Fine\u{2026} that works."])
    }

    @Test func anEllipsisBeforeACapitalStillEndsTheSentence() {
        var splitter = SentenceSplitter()
        #expect(splitter.feed("Done... Next up. ") == ["Done...", "Next up."])
    }

    @Test func anEllipsisAtTheChunkEdgeWaitsForTheNextWord() {
        var splitter = SentenceSplitter()
        #expect(splitter.feed("Fine... ").isEmpty)
        #expect(splitter.feed("that works. ") == ["Fine... that works."])
    }

    @Test func theDrawRulesAreCutOutOfAPromptWithTheirBlankLine() {
        #expect(TalkSightPolicy.withoutDrawInstructions("base\n\nRULES", drawInstructions: "RULES") == "base")
        #expect(TalkSightPolicy.withoutDrawInstructions("base", drawInstructions: "RULES") == "base")
        #expect(TalkSightPolicy.withoutDrawInstructions("base\n\nRULES", drawInstructions: "") == "base\n\nRULES")
    }

    private static let shot = ScreenShot(jpegData: Data([1]), label: "screen 1", pixelWidth: 10, pixelHeight: 10,
                                         displayFrame: .init(x: 0, y: 0, width: 10, height: 10))
    private static let drawText = "DRAW-RULES-BLOCK"

    @Test func marksAreRefusedWhenAnOlderClaudeStrippedTheImages() {
        let request = BrainRequest(transcript: "x", screenshots: [Self.shot], systemPrompt: "base\n\n" + Self.drawText,
                                   firstTextBudget: 8, carriesDrawImage: true)
        #expect(!TalkSightPolicy.drawAllowed(winner: "claude", request: request, supportsNoSessionPersistence: false,
                                             drawInstructions: Self.drawText))
        #expect(TalkSightPolicy.drawAllowed(winner: "claude", request: request, supportsNoSessionPersistence: true,
                                            drawInstructions: Self.drawText))
        #expect(!TalkSightPolicy.drawAllowed(winner: "codex", request: request, supportsNoSessionPersistence: true))
        let bare = BrainRequest(transcript: "x", systemPrompt: "base", firstTextBudget: 8)
        #expect(!TalkSightPolicy.drawAllowed(winner: "claude", request: bare, supportsNoSessionPersistence: true))
    }

    @Test func aStrippedLaunchDropsTheDrawInstructionsFromThePrompt() {
        let request = BrainRequest(transcript: "x", screenshots: [Self.shot], systemPrompt: "base\n\n" + Self.drawText,
                                   firstTextBudget: 8, carriesDrawImage: true)
        let stripped = TalkSightPolicy.launchRequest(request, voice: true, supportsNoSessionPersistence: false,
                                                     drawInstructions: Self.drawText)
        #expect(!stripped.systemPrompt.contains(Self.drawText))
        #expect(stripped.systemPrompt == "base")
        let kept = TalkSightPolicy.launchRequest(request, voice: true, supportsNoSessionPersistence: true,
                                                 drawInstructions: Self.drawText)
        #expect(kept.systemPrompt.contains(Self.drawText))
    }
}

@Suite("Ultron dialogue has no ellipsis")
struct UltronDialogueEllipsisLintTests {
    @Test func noDialogueLineContainsAnEllipsis() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/Zeus/Personality/ultron_dialogue.json"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let lines = try #require(object["generated_lines"] as? [[String: Any]])
        #expect(!lines.isEmpty)
        for entry in lines {
            let text = entry["text"] as? String ?? ""
            #expect(!text.contains("...") && !text.contains("\u{2026}"), "\(entry["id"] as? String ?? "?")")
        }
    }
}

@Suite("Ultron take C voice")
struct UltronTakeCVoiceTests {
    @Test func theStudioChoiceIsAKnownModelAndTheFastDefaultStays() {
        #expect(ElevenLabsQuality.studioModel == "eleven_multilingual_v2")
        #expect(ElevenLabsQuality.fastModel == "eleven_flash_v2_5")
        #expect(ElevenLabsQuality.resolve(stored: nil).modelID == "eleven_flash_v2_5")
    }

    @Test func takeCSettingsAreFasterAndSteadier() {
        let settings = UltronCloudVoice.elevenLabsSettings
        #expect(settings["stability"] == 0.6)
        #expect(settings["similarity_boost"] == 0.85)
        #expect(settings["style"] == 0.3)
        #expect(settings["speed"] == 1.0)
    }
}
