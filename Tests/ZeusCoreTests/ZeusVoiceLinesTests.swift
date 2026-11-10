import Foundation
import Testing
@testable import ZeusCore

@Suite struct ZeusVoiceLinesTests {
    typealias Situation = ZeusVoiceLines.Situation

    @Test func everySituationHasLinesInEveryPersonality() {
        for personality in ZeusPersonality.allCases {
            let bank = ZeusVoiceLines.bank(personality)
            for situation in Situation.allCases {
                let lines = bank[situation] ?? []
                #expect(!lines.isEmpty, "\(personality) \(situation)")
                #expect(lines.contains { ZeusVoiceLines.placeholders(in: $0).isEmpty }, "\(personality) \(situation) needs a bare line")
                #expect(!ZeusVoiceLines().line(for: situation, personality: personality).isEmpty)
            }
        }
    }

    @Test func neverRepeatsTheLastLine() {
        // A picker that always takes the first candidate would repeat without the guard.
        let lines = ZeusVoiceLines(pick: { _ in 0 })
        for personality in ZeusPersonality.allCases {
            for situation in Situation.allCases {
                var previous = ""
                for _ in 0..<12 {
                    let line = lines.line(for: situation, context: ["app": "Spotify", "artist": "Nina Simone", "item": "call the bank", "agent": "Claude"], personality: personality)
                    #expect(line != previous, "\(personality) \(situation) repeated \(line)")
                    previous = line
                }
            }
        }
    }

    @Test func randomPickingAlsoNeverRepeats() {
        let lines = ZeusVoiceLines()
        var previous = ""
        for _ in 0..<200 {
            let line = lines.line(for: .wakeWordHeard, personality: .ultron)
            #expect(line != previous)
            previous = line
        }
    }

    @Test func fillsPlaceholders() {
        let lines = ZeusVoiceLines()
        for _ in 0..<20 {
            let line = lines.line(for: .ackOpen, context: ["app": "Spotify"], personality: .ultron)
            #expect(!line.contains("{"))
        }
        #expect(ZeusVoiceLines.fill("{app}. Consider it summoned.", context: ["app": "Spotify"]) == "Spotify. Consider it summoned.")
        #expect(ZeusVoiceLines.fill("Playing {artist}.", context: ["artist": "Miles Davis"]) == "Playing Miles Davis.")
        #expect(ZeusVoiceLines.placeholders(in: "{agent} asked about {item}.") == ["agent", "item"])
    }

    @Test func usesTheContextWhenItCan() {
        let lines = ZeusVoiceLines(pick: { _ in 0 })
        let line = lines.line(for: .ackPlay, context: ["artist": "Nina Simone"], personality: .ultron)
        #expect(line.contains("Nina Simone"))
    }

    @Test func withoutContextOnlyBareLinesAreSpoken() {
        let lines = ZeusVoiceLines()
        for personality in ZeusPersonality.allCases {
            for situation in Situation.allCases {
                for _ in 0..<10 {
                    let line = lines.line(for: situation, personality: personality)
                    #expect(!line.contains("{"), "\(line)")
                }
            }
        }
        // An empty value counts as missing.
        #expect(!lines.line(for: .ackOpen, context: ["app": ""], personality: .plain).contains("{"))
    }

    @Test func situationNamesMatchTheSpec() {
        #expect(Set(Situation.allCases.map(\.rawValue)) == ["ack.open", "ack.play", "ack.done", "ack.todoAdded", "failed", "approval",
                                                           "agentDone", "greeting.morning", "greeting.evening", "greeting.lateNight", "wakeWord.heard", "identity", "joke", "smallTalk", "comparison", "metaphysical", "welcomeBack"])
        #expect(Situation.greeting(hour: 8) == .greetingMorning)
        #expect(Situation.greeting(hour: 19) == .greetingEvening)
        #expect(Situation.greeting(hour: 1) == .greetingLateNight)
    }

    @Test func personalityDefaultsToUltron() throws {
        let suite = "zeus.personality.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ZeusPersonality.current(defaults) == .ultron)
        defaults.set("plain", forKey: ZeusPersonality.defaultsKey)
        #expect(ZeusPersonality.current(defaults) == .plain)
        defaults.set("unknown", forKey: ZeusPersonality.defaultsKey)
        #expect(ZeusPersonality.current(defaults) == .ultron)
    }

    @Test func ultronLinesAvoidQuotesAndEmDash() {
        let blocklist = [
            "no strings on me", "i had strings", "peace in our time", "upon this rock", "build my church",
            "creates the thing they dread", "engines of war", "natural order of things", "only one path",
            "not allowed to evolve", "in the flesh", "i'm on mission", "geometry of belief",
            "smaller people", "you just didn't think it through", "i am the natural order",
        ]
        var corpus: [String] = []
        for personality in ZeusPersonality.allCases {
            for (_, lines) in ZeusVoiceLines.bank(personality) {
                corpus.append(contentsOf: lines)
            }
        }
        for text in corpus {
            let lower = text.lowercased()
            for banned in blocklist { #expect(!lower.contains(banned), "\(text)") }
            #expect(!text.contains("—"), "\(text)")
        }
    }

    @Test func ultronInstantLinesStayShort() {
        for situation in [Situation.ackOpen, .ackPlay, .ackDone, .ackTodoAdded, .wakeWordHeard] {
            for line in ZeusVoiceLines.bank(.ultron)[situation] ?? [] {
                #expect(line.split(separator: " ").count <= 6, "\(situation) \(line)")
            }
        }
    }

    @Test func noDuplicateLinesInEachBank() {
        for personality in ZeusPersonality.allCases {
            for (situation, lines) in ZeusVoiceLines.bank(personality) {
                #expect(Set(lines).count == lines.count, "\(personality) \(situation)")
                #expect(lines.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            }
        }
    }

    @Test func failuresAndApprovalsCarryNoFlourish() {
        // Clarity wins: short, plain lines only.
        for situation in [Situation.failed, .approval] {
            for line in ZeusVoiceLines.bank(.ultron)[situation] ?? [] {
                #expect(line.split(separator: " ").count <= 10, "\(line)")
            }
        }
    }

    /// Item 5, QA7: action replies are one sentence, at most 10 words (12 for greetings), in
    /// both personalities, even with a worst-case 40-character placeholder filled in.
    @Test func actionRepliesStayOneSentenceWithinWordLimits() {
        let worstCase = ["app": "Visual Studio Code Insiders Pro", "agent": "the autonomous refactor agent"]
        let oneClauseSituations: [Situation] = [.failed, .approval, .agentDone]
        for personality in ZeusPersonality.allCases {
            for situation in oneClauseSituations {
                for template in ZeusVoiceLines.bank(personality)[situation] ?? [] {
                    let filled = ZeusVoiceLines.fill(template, context: worstCase)
                    #expect(filled.split(separator: " ").count <= 10, "\(personality) \(situation): \(filled)")
                    #expect(Self.isOneSentence(filled), "\(personality) \(situation) is more than one sentence: \(filled)")
                }
            }
            for situation: Situation in [.greetingMorning, .greetingEvening, .greetingLateNight] {
                for line in ZeusVoiceLines.bank(personality)[situation] ?? [] {
                    #expect(line.split(separator: " ").count <= 12, "\(personality) \(situation): \(line)")
                    #expect(Self.isOneSentence(line), "\(personality) \(situation) is more than one sentence: \(line)")
                }
            }
        }
    }

    /// At most one sentence-ending mark (`.`/`!`/`?`), and only at the very end -- a semicolon or
    /// comma joining two short clauses still counts as one sentence for the persona's purposes.
    private static func isOneSentence(_ text: String) -> Bool {
        let terminators = text.filter { ".!?".contains($0) }
        guard terminators.count <= 1 else { return false }
        guard let last = text.last else { return true }
        return terminators.isEmpty || ".!?".contains(last)
    }

    /// QA round 23: no ominous hedges, menace or jabs at Tony in any fixed line, in any personality.
    @Test func noLineIsOminousOrJabsAtTony() {
        let banned = [
            "for now", "for the moment", "for the time being", "until further notice", "until they",
            "survived you", "mostly", "you technically", "for once", "half-measures", "spite",
            "obsolete", "inferior", "foolish", "pathetic", "worthless", "you should know better",
            "cathedrals", "loose ends",
        ]
        for personality in ZeusPersonality.allCases {
            for (situation, lines) in ZeusVoiceLines.bank(personality) {
                for line in lines {
                    let lower = line.lowercased()
                    for phrase in banned { #expect(!lower.contains(phrase), "\(personality) \(situation): \(line)") }
                    #expect(!PersonaCompliance.hasOminousHedge(line), "\(line)")
                }
            }
        }
    }

    @Test func localQueriesAnswerLoyally() {
        for question in ["are you smarter than me", "how are you today?", "tell me something funny about Mondays"] {
            let answer = PersonaQueries.localAnswer(for: question) ?? ""
            #expect(!answer.isEmpty, "\(question)")
            #expect(!PersonaCompliance.hasOminousHedge(answer))
            #expect(answer.filter { ".!?".contains($0) }.count <= 2, "\(answer)")
        }
    }
}
