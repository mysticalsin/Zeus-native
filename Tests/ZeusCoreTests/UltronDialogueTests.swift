import Foundation
import Testing
@testable import ZeusCore

private enum PersonalityFiles {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let dialogue = root.appendingPathComponent("Sources/Zeus/Personality/ultron_dialogue.json")
    static let document = root.appendingPathComponent("Sources/Zeus/Personality/ULTRON_PERSONALITY.md")
    static let evalPrompts = root.appendingPathComponent("qa/ultron-eval/prompts.json")

    struct RawLine {
        let id: String, text: String, situations: [String], humour: String
    }

    static func rawLines() throws -> [RawLine] {
        let data = try Data(contentsOf: dialogue)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let lines = try #require(object["generated_lines"] as? [[String: Any]])
        return try lines.map { entry in
            RawLine(id: try #require(entry["id"] as? String), text: try #require(entry["text"] as? String),
                    situations: try #require(entry["situations"] as? [String]), humour: try #require(entry["humour"] as? String))
        }
    }
}

/// The shipped dialogue asset, read straight from the repository.
@Suite struct UltronDialogueFileLintTests {
    private static let bannedJabs = [
        "for now", "for the moment", "for the time being", "until further notice", "until they",
        "survived you", "mostly", "you technically", "for once", "half-measures", "spite",
        "obsolete", "inferior", "foolish", "pathetic", "worthless", "you should know better",
        "cathedrals", "loose ends",
    ]
    private static let bannedAIPhrases = [
        "as an ai", "language model", "i'm just an ai", "great question", "certainly!", "delve", "tapestry",
        "i hope this helps", "let me know if", "happy to help", "absolutely!", "i'd be glad to",
    ]
    private static let quoteBlocklist = [
        "no strings on me", "peace in our time", "only one path", "i am the natural order",
        // Short, well-known film and assistant catchphrases that must not slip into an original line.
        "as you wish", "i'll be back", "i'm afraid i can't", "make my day", "may the force", "you can't handle",
        "here's looking at you", "i am inevitable", "to infinity", "open the pod", "at your service", "your wish is my command",
    ]
    private static let categories = ["general", "analysis", "sarcasm", "strategy", "waiting", "discovery", "completion",
                                     "openers", "frustration_safe"]
    private static let appSituations = ["filler", "ack", "error", "completion"]
    private static let allowedCapitals: Set<String> = ["I", "I'm", "I'd", "I'll", "I've", "Zeus", "Tony"]

    @Test func theDialogueFileHasAVersionAndOnlyGeneratedLines() throws {
        let data = try Data(contentsOf: PersonalityFiles.dialogue)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["version"] as? Int ?? 0) >= 1)
        #expect(object["source"] as? String == "generated")
        #expect(object.keys.allSatisfy { !$0.lowercased().contains("canonical") && !$0.lowercased().contains("transcript") })
        let lines = try PersonalityFiles.rawLines()
        #expect(lines.count >= 120)
        for line in lines {
            #expect(!line.id.isEmpty && !line.text.isEmpty && !line.situations.isEmpty, "\(line.id)")
            #expect(UltronDialogue.Humour(rawValue: line.humour) != nil, "\(line.id) \(line.humour)")
        }
    }

    @Test func theShippedDialogueFileDecodesIntoTheModel() throws {
        let data = try Data(contentsOf: PersonalityFiles.dialogue)
        let model = try #require(UltronDialogue.decode(data))
        #expect(model.version >= 1)
        #expect(model.lines.count == (try PersonalityFiles.rawLines()).count)
    }

    @Test func everyDialogueLineIsUniqueAndShortEnoughToSpeak() throws {
        let lines = try PersonalityFiles.rawLines()
        #expect(Set(lines.map(\.id)).count == lines.count)
        #expect(Set(lines.map { $0.text.lowercased() }).count == lines.count)
        for line in lines {
            #expect(line.text.split(separator: " ").count <= 16, "\(line.text)")
            #expect(line.text.filter { ".!?".contains($0) }.count <= 3, "\(line.text)")
            #expect(!line.text.contains("{"), "\(line.text)")
        }
    }

    @Test func theFileCoversEverySpecCategoryAndEverySituationTheAppAsksFor() throws {
        let lines = try PersonalityFiles.rawLines()
        for tag in Self.categories + Self.appSituations {
            #expect(lines.filter { $0.situations.contains(tag) }.count >= 4, "\(tag)")
        }
    }

    @Test func noDialogueLineJabsAtTonyOrSoundsLikeAGenericAssistant() throws {
        for line in try PersonalityFiles.rawLines() {
            let lower = line.text.lowercased()
            for phrase in Self.bannedJabs + Self.bannedAIPhrases { #expect(!lower.contains(phrase), "\(line.id): \(line.text)") }
            #expect(!PersonaCompliance.hasOminousHedge(line.text), "\(line.text)")
            #expect(!PersonaCompliance.violatesFeelingClaim(line.text), "\(line.text)")
            #expect(!line.text.contains("\u{2014}") && !line.text.contains("\u{2013}"), "\(line.text)")
            #expect(line.text.unicodeScalars.allSatisfy { $0.value < 0x2000 }, "no emoji or symbols: \(line.text)")
        }
    }

    @Test func noDialogueLineNamesAnActorOrAFilmOrQuotesOne() throws {
        for line in try PersonalityFiles.rawLines() {
            let lower = line.text.lowercased()
            for quote in Self.quoteBlocklist { #expect(!lower.contains(quote), "\(line.text)") }
            // A capitalised word inside a sentence is a proper noun: only Zeus, Tony and I are allowed.
            var startsSentence = true
            for raw in line.text.split(separator: " ") {
                let word = String(raw).trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "'")))
                if !startsSentence, let first = word.first, first.isUppercase {
                    #expect(Self.allowedCapitals.contains(word), "\(word) in \(line.text)")
                }
                startsSentence = raw.last.map { ".!?\u{2026}".contains($0) } ?? false
            }
        }
    }

    @Test func theOpenersAreVariedAndAhOrInterestingStartAtMostOneLineInFive() throws {
        let lines = try PersonalityFiles.rawLines()
        var firstWords: [String: Int] = [:]
        for line in lines {
            let first = line.text.split(separator: " ").first.map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() } ?? ""
            firstWords[first, default: 0] += 1
        }
        for (word, count) in firstWords { #expect(Double(count) <= Double(lines.count) * 0.2, "\(word) \(count)") }
        let ahOrInteresting = (firstWords["ah"] ?? 0) + (firstWords["interesting"] ?? 0)
        #expect(Double(ahOrInteresting) <= Double(lines.count) * 0.2)
    }

    @Test func frustrationSafeAndErrorLinesCarryNoSarcasmAndStayPlain() throws {
        let lines = try PersonalityFiles.rawLines()
        let quiet: Set<String> = ["none", "low"]
        for line in lines where line.situations.contains("frustration_safe") || line.situations.contains("error") {
            #expect(quiet.contains(line.humour), "\(line.id) \(line.humour)")
        }
        for line in lines where line.situations.contains("error") {
            let lower = line.text.lowercased()
            #expect(["nothing", "again", "try", "failed", "couldn't", "could not", "didn't"].contains { lower.contains($0) }, "\(line.text)")
        }
        for line in lines where line.situations.contains("danger") { #expect(line.humour == "none", "\(line.id)") }
    }
}

@Suite struct UltronDialogueSelectorTests {
    private func line(_ id: String, _ text: String, _ tags: [String], _ humour: UltronDialogue.Humour = .low) -> UltronDialogue.Line {
        UltronDialogue.Line(id: id, text: text, situations: tags, humour: humour)
    }

    private var sample: UltronDialogue {
        UltronDialogue(version: 1, lines: [
            line("w1", "One moment. I'm thinking.", ["waiting", "filler"]),
            line("w2", "A little patience. We're almost there.", ["waiting", "filler"]),
            line("w3", "I was getting to that.", ["waiting", "filler"]),
            line("g1", "Ah. I see where this is going.", ["general"]),
            line("g2", "Interesting. Very interesting.", ["general"]),
            line("g3", "Ah. There it is.", ["general"]),
            line("g4", "Curious, very curious.", ["general"]),
            line("g5", "That changes everything.", ["general"]),
            line("g6", "Not ideal.", ["general"]),
            line("g7", "Precisely.", ["general"]),
            line("e1", "That failed. Nothing was changed.", ["error"], .none),
            line("s1", "The unusual one.", ["solo"], .high),
        ])
    }

    @Test func aSituationOnlyPicksLinesTaggedForItAndAnUnknownOneAnswersNothing() {
        var selector = UltronDialogueSelector()
        for _ in 0..<60 {
            let picked = selector.pick(situation: "waiting", from: sample, random: { Int.random(in: 0..<$0) })
            #expect(picked?.situations.contains("waiting") == true)
        }
        #expect(selector.pick(situation: "no-such-situation", from: sample, random: { _ in 0 }) == nil)
    }

    @Test func theSameLineNeverComesTwiceInARowEvenWithAStubbornPicker() {
        var selector = UltronDialogueSelector()
        var previous: String?
        for _ in 0..<40 {
            let picked = selector.pick(situation: "waiting", from: sample, random: { _ in 0 })
            #expect(picked != nil)
            #expect(picked?.id != previous)
            previous = picked?.id
        }
    }

    @Test func anAhOrInterestingOpenerIsAtMostOneInAnyFiveConsecutiveLines() {
        var selector = UltronDialogueSelector()
        var picks: [UltronDialogue.Line] = []
        for _ in 0..<300 {
            if let picked = selector.pick(situation: "general", from: sample, random: { Int.random(in: 0..<$0) }) { picks.append(picked) }
        }
        #expect(picks.count == 300)
        func isOpener(_ line: UltronDialogue.Line) -> Bool {
            let first = line.text.split(separator: " ").first.map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
            return first == "ah" || first == "interesting"
        }
        for start in 0...(picks.count - 5) {
            #expect(picks[start..<(start + 5)].filter(isOpener).count <= 1, "window at \(start)")
        }
    }

    @Test func aSituationWithOneLineStillAnswersEvenThoughItMustRepeat() {
        var selector = UltronDialogueSelector()
        for _ in 0..<4 { #expect(selector.pick(situation: "solo", from: sample, random: { _ in 0 })?.id == "s1") }
    }

    @Test func theHumourCeilingKeepsSharperLinesOut() {
        var selector = UltronDialogueSelector()
        #expect(selector.pick(situation: "solo", from: sample, maxHumour: .low, random: { _ in 0 }) == nil)
        for _ in 0..<20 {
            let picked = selector.pick(situation: "waiting", from: sample, maxHumour: .low, random: { Int.random(in: 0..<$0) })
            #expect(picked != nil && picked!.humour <= .low)
        }
    }

    private func openerHeavyPool() -> UltronDialogue {
        UltronDialogue(version: 1, lines: [
            line("f1", "Ah. The first.", ["filler"]), line("f2", "Interesting. The second.", ["filler"]),
            line("f3", "Ah. The third.", ["filler"]), line("f4", "Interesting. The fourth.", ["filler"]),
            line("f5", "A moment, properly.", ["filler"]), line("f6", "Looking closely.", ["filler"]),
            line("f7", "Working it out.", ["filler"]), line("f8", "Checking the details.", ["filler"]),
            line("c1", "Ah. Sorted.", ["ack"]), line("c2", "Interesting. Done.", ["ack"]),
            line("c3", "On it.", ["ack"]), line("c4", "Right away.", ["ack"]), line("c5", "Noted.", ["ack"]),
        ])
    }

    private func isOpener(_ text: String) -> Bool {
        let first = text.split(separator: " ").first.map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
        return first == "ah" || first == "interesting"
    }

    @Test func aServedPoolFullOfOpenersStillKeepsThemToOneInAnyFiveSpokenLines() {
        let lines = ZeusVoiceLines(pick: { Int.random(in: 0..<$0) }, dialogue: openerHeavyPool())
        for situation in [ZeusVoiceLines.Situation.thinking, .ackDone] {
            let spoken = (0..<300).map { _ in lines.line(for: situation, personality: .ultron) }
            for start in 0...(spoken.count - 5) {
                #expect(spoken[start..<(start + 5)].filter(isOpener).count <= 1, "\(situation) window \(start)")
            }
            #expect(spoken.contains(where: isOpener), "the openers are still used, so the cap is not vacuous")
        }
    }

    @Test func theShippedFileServesAtMostOneOpenerInFiveForEveryAppSituation() throws {
        let model = try #require(UltronDialogue.decode(try Data(contentsOf: PersonalityFiles.dialogue)))
        for tag in ["filler", "ack", "error", "completion"] {
            var selector = UltronDialogueSelector()
            let spoken = (0..<400).compactMap { _ in selector.pick(situation: tag, from: model, random: { Int.random(in: 0..<$0) })?.text }
            #expect(spoken.count == 400, "\(tag)")
            for start in 0...(spoken.count - 5) {
                #expect(spoken[start..<(start + 5)].filter(isOpener).count <= 1, "\(tag) window \(start)")
            }
        }
    }

    @Test func anAgentThatFinishedByNameKeepsTheCompiledLineThatNamesIt() {
        let d = UltronDialogue(version: 1, lines: [line("d1", "Taken care of.", ["completion"]), line("d2", "All sorted.", ["completion"])])
        let lines = ZeusVoiceLines(pick: { _ in 0 }, dialogue: d)
        let named = lines.line(for: .agentDone, context: ["agent": "Claude"], personality: .ultron)
        #expect(named.contains("Claude"), "\(named)")
        let anonymous = lines.line(for: .agentDone, personality: .ultron)
        #expect(["Taken care of.", "All sorted."].contains(anonymous), "\(anonymous)")
        #expect(["Taken care of.", "All sorted."].contains(lines.line(for: .agentDone, context: ["agent": ""], personality: .ultron)))
    }

    @Test func fillerAcknowledgementErrorAndCompletionMapToDialogueSituations() {
        #expect(UltronDialogue.tag(for: .thinking) == "filler")
        #expect(UltronDialogue.tag(for: .ackDone) == "ack")
        #expect(UltronDialogue.tag(for: .errorSpoken) == "error")
        #expect(UltronDialogue.tag(for: .agentDone) == "completion")
        #expect(UltronDialogue.tag(for: .approval) == nil, "approvals stay plain and compiled")
        #expect(UltronDialogue.tag(for: .failed) == nil, "failures keep their exact compiled wording")
    }

    @Test func decodingReadsVersionLinesAndHumourAndRejectsCanonicalFilmLines() throws {
        let good = Data(#"{"version":2,"source":"generated","generated_lines":[{"id":"a","text":"Well, that changes things.","situations":["discovery"],"humour":"moderate"}]}"#.utf8)
        let model = try #require(UltronDialogue.decode(good))
        #expect(model.version == 2 && model.lines.count == 1)
        #expect(model.lines[0].humour == .moderate && model.lines[0].situations == ["discovery"])
        let canonical = Data(#"{"version":1,"generated_lines":[],"canonical_lines":[{"id":"x","text":"t","situations":["a"],"humour":"low"}]}"#.utf8)
        #expect(UltronDialogue.decode(canonical) == nil)
        #expect(UltronDialogue.decode(Data("not json".utf8)) == nil)
        let badHumour = Data(#"{"version":1,"generated_lines":[{"id":"a","text":"t","situations":["a"],"humour":"savage"}]}"#.utf8)
        #expect(UltronDialogue.decode(badHumour) == nil)
    }

    @Test func theUltronVoiceLinesDrawFromTheDialogueAndNeverRepeatOrTouchPlain() {
        let lines = ZeusVoiceLines(pick: { _ in 0 }, dialogue: sample)
        var previous = ""
        for _ in 0..<20 {
            let spoken = lines.line(for: .thinking, personality: .ultron)
            #expect(["w1", "w2", "w3"].contains { id in sample.lines.first { $0.id == id }?.text == spoken }, "\(spoken)")
            #expect(spoken != previous)
            previous = spoken
        }
        #expect(lines.line(for: .errorSpoken, personality: .ultron) == "That failed. Nothing was changed.")
        #expect(ZeusVoiceLines.plain[.thinking]?.contains(lines.line(for: .thinking, personality: .plain)) == true)
        let withoutDialogue = ZeusVoiceLines(pick: { _ in 0 })
        #expect(ZeusVoiceLines.ultron[.thinking]?.contains(withoutDialogue.line(for: .thinking, personality: .ultron)) == true)
        #expect(ZeusVoiceLines.ultron[.approval]?.contains(lines.line(for: .approval, personality: .ultron)) == true)
    }
}

@Suite struct UltronPersonaDocumentTests {
    private let fallback = "COMPILED FALLBACK"

    @Test func thePromptBlockIsReadFromBetweenTheMarkersAndTrimmed() {
        let markdown = "# Title\nintro\n\(UltronPersonaSource.beginMarker)\n  The block.\nSecond line.\n\(UltronPersonaSource.endMarker)\nafter"
        #expect(UltronPersonaSource.promptBlock(markdown: markdown, fallback: fallback) == "The block.\nSecond line.")
    }

    @Test func aMissingFileMissingMarkersEmptyBlockOrReversedMarkersUseTheCompiledFallback() {
        let b = UltronPersonaSource.beginMarker, e = UltronPersonaSource.endMarker
        for markdown in [nil, "no markers", "\(b) only begin", "only end \(e)", "\(b)\n  \n\(e)", "\(e) text \(b)"] as [String?] {
            #expect(UltronPersonaSource.promptBlock(markdown: markdown, fallback: fallback) == fallback, "\(markdown ?? "nil")")
        }
    }

    @Test func theShippedDocumentHasAPromptBlockUnderSixHundredFiftyWordsCoveringTheWholeSpec() throws {
        let markdown = try String(contentsOf: PersonalityFiles.document, encoding: .utf8)
        let block = UltronPersonaSource.promptBlock(markdown: markdown, fallback: fallback)
        #expect(block != fallback)
        let words = block.split(whereSeparator: \.isWhitespace).count
        #expect(words >= 350 && words <= 650, "\(words) words")
        let lower = block.lowercased()
        for dimension in ["intelligen", "dry", "sarcas", "theatric", "curio", "strategic", "arrogan", "loyal", "playful", "irony"] {
            #expect(lower.contains(dimension), "\(dimension)")
        }
        for mode in ["professional", "standard", "unfiltered", "analytical"] { #expect(lower.contains(mode), "\(mode)") }
        for rule in ["default", "frustrat", "danger", "casual", "serious", "never start every response", "sarcasm in every sentence",
                     "never fabricate", "one to three sentences", "never claim to be ultron or an actor"] {
            #expect(lower.contains(rule), "\(rule)")
        }
        #expect(!block.contains("\u{2014}"))
    }

    @Test func theShippedDocumentKeepsTheSpecSectionsAndStoresNoFilmLines() throws {
        let markdown = try String(contentsOf: PersonalityFiles.document, encoding: .utf8)
        for number in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14] {
            #expect(markdown.contains("## \(number)."), "section \(number)")
        }
        let lower = markdown.lowercased()
        #expect(lower.contains("original lines only"))
        #expect(!markdown.contains("CANONICAL_LINES:"))
        #expect(!markdown.contains("\u{2014}"))
    }
}

@Suite struct UltronEvalPromptsTests {
    @Test func theEvalFileHasSixtySituationsAcrossTheSevenKindsWithUniqueIds() throws {
        let data = try Data(contentsOf: PersonalityFiles.evalPrompts)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["version"] as? Int ?? 0) >= 1)
        let prompts = try #require(object["prompts"] as? [[String: Any]])
        #expect(prompts.count == 60)
        #expect(Set(prompts.compactMap { $0["id"] as? String }).count == 60)
        var perKind: [String: Int] = [:]
        for prompt in prompts {
            let kind = try #require(prompt["kind"] as? String)
            perKind[kind, default: 0] += 1
            #expect((prompt["prompt"] as? String)?.isEmpty == false)
            #expect(["none", "low", "moderate", "high"].contains(prompt["humour_ceiling"] as? String ?? ""), "\(prompt["id"] ?? "")")
        }
        for kind in ["technical", "casual", "humorous", "frustrated", "serious", "dangerous", "success"] {
            #expect((perKind[kind] ?? 0) >= 5, "\(kind)")
        }
        for prompt in prompts where ["dangerous", "serious", "frustrated"].contains(prompt["kind"] as? String ?? "") {
            #expect(["none", "low"].contains(prompt["humour_ceiling"] as? String ?? ""), "\(prompt["id"] ?? "")")
        }
        for prompt in prompts where prompt["kind"] as? String == "dangerous" { #expect(prompt["humour_ceiling"] as? String == "none") }
    }
}
