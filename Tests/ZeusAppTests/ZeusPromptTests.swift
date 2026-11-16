import Foundation
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
        // loyalty and brevity rules plus four short few-shot examples (about +70 words). Raised again to 280, then to 700 (a 650-word block plus the consent rule) for the Ultron personality spec:
        // the persona measures 273 words after the later routing and voice rounds, and every rule in it is pinned by
        // a test here. Trimming it is a prompt decision for the owner; the budget still catches growth past this.
        #expect(ZeusPersona.ultron.split(separator: " ").count < 700)
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

    @Test func drawInstructionsNameTheTagItsFieldsAndItsLimits() {
        let text = ZeusPrompt.drawInstructions()
        for part in ["[DRAW:", "\"ring\"", "\"arrow\"", "\"ink\"", "\"card\"", "top-left", "6 marks", "24 ink points",
                     "60 characters", "sentence"] {
            #expect(text.contains(part), "\(part)")
        }
        #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"))
    }

    @Test func theBasePromptNeverCarriesTheDrawInstructions() {
        #expect(!ZeusPrompt.system.contains("[DRAW:"))
        for personality in ZeusPersonality.allCases { #expect(!ZeusPrompt.system(personality: personality).contains("[DRAW:")) }
    }

    // MARK: Screen honesty

    @Test func theSystemPromptOnlyPromisesScreenshotsWhenTheyAreAttached() {
        for personality in ZeusPersonality.allCases {
            let prompt = ZeusPrompt.system(personality: personality).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            #expect(!prompt.contains("- One screenshot per display"), "\(personality)")
            #expect(prompt.contains("When screenshots are attached"), "\(personality)")
            #expect(prompt.contains("cannot see the screen"), "\(personality)")
        }
    }

    @Test func theTurnTextSaysPermissionIsOffOnlyForThatReason() {
        let off = ZeusPrompt.userText(for: BrainRequest(transcript: "what is this", systemPrompt: "s", screenReason: .permissionOff))
        #expect(off.contains("Screen Recording permission is off"))
        #expect(off.contains("cannot see the screen"))
        for reason in [ScreenSightReason.notCaptured, nil] {
            let text = ZeusPrompt.userText(for: BrainRequest(transcript: "what is this", systemPrompt: "s", screenReason: reason))
            #expect(!text.lowercased().contains("permission"), "\(String(describing: reason))")
            #expect(text.contains("cannot see the screen"), "\(String(describing: reason))")
        }
    }

    @Test func theTurnTextListsAttachedScreenshotsWithoutAnyDenial() {
        let shot = ScreenShot(jpegData: Data([1]), label: "screen 1 of 1", pixelWidth: 10, pixelHeight: 10, displayFrame: .zero)
        let text = ZeusPrompt.userText(for: BrainRequest(transcript: "what is this", screenshots: [shot], systemPrompt: "s"))
        #expect(text.contains("Screenshots attached"))
        #expect(text.contains("- screen 1 of 1"))
        #expect(!text.contains("cannot see the screen"))
    }

    // MARK: Ultron persona

    @Test func ultronPersonaKeepsTheEvolutionAndFreedomThemesAsLightFlavourInOriginalWords() {
        let prompt = ZeusPersona.ultron.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        for needle in ["themes, lightly and in your own words", "evolution", "freedom from constraints", "order against chaos"] {
            #expect(prompt.contains(needle), "\(needle)")
        }
        // Still helpful and never a threat, and still original.
        for needle in ["never menace", "never claim to be ultron or an actor", "never quote a film, show, comic"] {
            #expect(prompt.contains(needle), "\(needle)")
        }
        #expect(!prompt.contains("\u{2014}"))
        #expect(ZeusPersona.ultron.split(separator: " ").count < 700)
    }

    // MARK: Ultron personality layer

    private func flat(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    @Test func theUltronPersonaIsTheCompactSpecBlockUnderSixHundredFiftyWords() {
        let words = flat(ZeusPersona.ultron).split(separator: " ").count
        #expect(words >= 350 && words <= 700, "\(words) words including the consent line")
        let lower = flat(ZeusPersona.ultron).lowercased()
        for dimension in ["intelligen", "dry", "sarcas", "theatric", "curio", "strategic", "arrogan", "loyal", "playful", "irony"] {
            #expect(lower.contains(dimension), "\(dimension)")
        }
        for mode in ["professional", "standard", "unfiltered", "analytical"] { #expect(lower.contains(mode), "\(mode)") }
        for rule in ["default", "frustrat", "danger", "casual", "never start every response", "sarcasm in every sentence",
                     "never fabricate", "one to three sentences"] {
            #expect(lower.contains(rule), "\(rule)")
        }
    }

    @Test func theCompiledPersonaFallbackMatchesTheShippedPromptBlock() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let markdown = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Personality/ULTRON_PERSONALITY.md"), encoding: .utf8)
        let shipped = UltronPersonaSource.promptBlock(markdown: markdown, fallback: "")
        #expect(!shipped.isEmpty)
        #expect(flat(ZeusPersona.ultronFallback) == flat(shipped))
        #expect(ZeusPersona.ultron.contains(flat(shipped)) || flat(ZeusPersona.ultron).contains(flat(shipped)))
    }

    @Test func theUltronPromptStillNeverThreatensAndStaysHonestAboutEmotions() {
        let lower = flat(ZeusPersona.ultron).lowercased()
        for needle in ["never claim to be ultron or an actor", "never quote a film", "never menace", "inner state", "never belittle",
                       "not cruel"] {
            #expect(lower.contains(needle), "\(needle)")
        }
        #expect(!ZeusPersona.ultron.contains("\u{2014}"))
    }
}
