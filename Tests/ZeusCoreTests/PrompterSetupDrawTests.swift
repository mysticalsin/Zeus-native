import Testing
@testable import ZeusCore

struct PrompterSetupDrawTests {
    private func cards(_ plan: PrompterSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theSwitchesThatAreOnFollowPrompt() {
        let usual = PrompterSetupDraw.plan(words: ["Private", "Countdown"])
        #expect(cards(usual) == ["Prompt", "Private", "Countdown"])
        #expect(PrompterSetupAsk.line(words: ["Private", "Countdown"]) == "The prompter has Private and Countdown on.")
        #expect(usual.boltCaption(at: 0) == "Prompt")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Countdown")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        let all = PrompterSetupAsk.order
        #expect(cards(PrompterSetupDraw.plan(words: all)) == ["Prompt", "Follow", "Slides", "Private", "Mirror"])
        #expect(PrompterSetupAsk.line(words: all) == "The prompter has 5 on, starting Follow, Slides, Private, and Mirror.")
        #expect(cards(PrompterSetupDraw.plan(words: [])) == ["Prompt", "None"])
        #expect(PrompterSetupAsk.line(words: []) == "The prompter settings are off.")
        #expect(PrompterSetupAsk.line(words: ["Follow"]) == "The prompter has Follow on.")
        #expect(cards(PrompterSetupDraw.plan(words: ["Countdown", "Follow"])) == ["Prompt", "Can't"])
        #expect(PrompterSetupAsk.line(words: ["Beep"]) == "I can't read the prompter settings.")
    }

    @Test func theRollingScriptStaysOffThisAsk() {
        #expect(PrompterSetupAsk.matches("how's the prompter set"))
        #expect(PrompterSetupAsk.matches("Hey Zeus, which prompter settings?"))
        #expect(PrompterSetupAsk.matches("prompter settings"))
        #expect(!PrompterSetupAsk.matches("how's the prompter"))
        #expect(!PrompterSetupAsk.matches("prompter"))
        #expect(!PrompterSetupAsk.matches("what's on day to day"))
        #expect(!PrompterSetupAsk.matches("which voice cues"))
    }
}
