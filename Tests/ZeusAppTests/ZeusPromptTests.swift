import Testing
import ZeusCore
@testable import Zeus

@Suite("ZEUS voice persona")
struct ZeusPromptTests {
    @Test func ultronPersonaIsInEveryPrompt() {
        for prompt in [ZeusPrompt.system(personality: .ultron), ChatPrompt.system(personality: .ultron)] {
            #expect(prompt.contains(ZeusPersona.ultron))
            #expect(prompt.contains("loyal to Tony"))
            #expect(prompt.contains("Theatrical calm"))
            #expect(prompt.contains("at most one\nflourish") || prompt.contains("at most one flourish"))
            #expect(prompt.contains("No flourish for errors, approvals"))
            #expect(prompt.contains("Never quote a film"))
            #expect(prompt.contains("never at Tony"))
        }
    }

    @Test func plainPersonaDropsTheFlourishes() {
        let prompt = ZeusPrompt.system(personality: .plain)
        #expect(prompt.contains(ZeusPersona.plain))
        #expect(prompt.contains("No flourishes or jokes"))
        #expect(!prompt.contains("Theatrical calm"))
    }

    @Test func everyPersonaKeepsTonyInControl() {
        for personality in ZeusPersonality.allCases {
            for prompt in [ZeusPrompt.system(personality: personality), ChatPrompt.system(personality: personality)] {
                #expect(prompt.contains("Never send a message or act on Tony's behalf unless he asks"))
                #expect(prompt.contains("approval"))
            }
        }
    }

    @Test func ultronPromptHasToneRulesAndExamples() {
        let prompt = ZeusPersona.ultron.lowercased()
        for needle in ["for now", "for the moment", "never belittle", "never menace", "one dry wry turn",
                       "one or two short sentences", "at most 10 words"] {
            #expect(prompt.contains(needle), "\(needle)")
        }
        #expect(prompt.components(separatedBy: "\n").filter { $0.contains("? ") }.count >= 4)
        // The examples themselves must not contain ominous hedges.
        let examples = prompt.components(separatedBy: "examples:").last ?? ""
        #expect(!PersonaCompliance.hasOminousHedge(examples))
    }

    @Test func ultronPromptForbidsFeelingClaims() {
        let prompt = ZeusPersona.ultron.lowercased()
        #expect(prompt.contains("never describe feelings"))
        #expect(prompt.contains("inner state"))
    }

    @Test func personaComplianceFlagsQARegressionLine() {
        #expect(PersonaCompliance.violatesFeelingClaim(
            "But there's something like wear in handling loose threads that won't untangle."))
    }

    @Test func ultronPromptAvoidsQuoteBlocklist() {
        let blocklist = [
            "no strings on me", "peace in our time", "only one path", "i am the natural order",
        ]
        let prompt = ZeusPersona.ultron.lowercased()
        for banned in blocklist { #expect(!prompt.contains(banned)) }
        #expect(!ZeusPersona.ultron.contains("—"))
    }

    @Test func personaSectionStaysCompact() {
        // It is sent on every turn. Raised from 160 to 240 in round 24 for the explicit no-menace,
        // loyalty and brevity rules plus four short few-shot examples (about +70 words).
        #expect(ZeusPersona.ultron.split(separator: " ").count < 240)
        #expect(ZeusPersona.plain.split(separator: " ").count < 90)
    }

    /// Item 5, QA7: both personas must tell the model to keep action replies to one short sentence.
    @Test func everyPersonaCapsActionRepliesAtTenWords() {
        for personality in ZeusPersonality.allCases {
            let persona = ZeusPersona.instructions(for: personality)
            #expect(persona.contains("at most 10"), "\(personality)")
            #expect(persona.contains("no quotes"), "\(personality)")
        }
    }

    @Test func promptDocumentsTheTerminalAndResearchTags() {
        let prompt = ZeusPrompt.system(personality: .plain)
        for tag in ["terminal.agent", "terminal.open", "terminal.run", #""type":"research""#, "browser.agent", "mac.drive"] {
            #expect(prompt.contains(tag), "\(tag)")
        }
        #expect(prompt.contains("anything that deletes, overwrites, installs or uses the network asks Tony first"))
        // every documented tag is one the parser knows
        for kind in [ZeusAction.Kind.terminalAgent, .terminalOpen, .terminalRun, .research] { #expect(prompt.contains(kind.rawValue)) }
    }
}
