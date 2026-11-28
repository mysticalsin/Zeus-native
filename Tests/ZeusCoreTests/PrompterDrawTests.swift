import Testing
@testable import ZeusCore

struct PrompterDrawTests {
    private func cards(_ plan: PrompterDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aWrittenScriptDrawsTheTwoCounts() {
        let plan = PrompterDraw.plan(seen: true, words: 12, cues: 2, live: nil)
        #expect(cards(plan) == ["Script", "12", "2"])
        #expect(PrompterAsk.line(seen: true, words: 12, cues: 2, live: nil) == "Your script has 12 words and 2 cues.")
        #expect(PrompterAsk.line(seen: true, words: 1, cues: 1, live: nil) == "Your script has 1 word and 1 cue.")
        #expect(plan.boltCaption(at: 0) == "Script")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "12")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap * 2) == "2")
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        let empty = PrompterDraw.plan(seen: true, words: 0, cues: 0, live: nil)
        #expect(cards(empty) == ["Script", "None"])
        #expect(PrompterAsk.line(seen: true, words: 0, cues: 0, live: nil) == "No script yet.")
        #expect(cards(PrompterDraw.plan(seen: false, words: 12, cues: 2, live: nil)) == ["Script", "Can't"])
        #expect(PrompterAsk.line(seen: false, words: 12, cues: 2, live: nil) == "I can't read the script.")
        let secret = PrompterDraw.plan(seen: true, words: 4, cues: 0, live: nil)
        #expect(!cards(secret).joined(separator: " ").contains("password"))
    }

    @Test func aRollingPrompterDrawsThePageWord() {
        let rolling = PrompterDraw.plan(seen: true, words: 12, cues: 2, live: "Rolling")
        #expect(cards(rolling) == ["Script", "Rolling"])
        #expect(PrompterAsk.line(seen: true, words: 12, cues: 2, live: "Rolling") == "The prompter is rolling.")
        #expect(rolling.boltCaption(at: ExplainBeatSchedule.gap) == "Rolling")
        #expect(rolling.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(PrompterAsk.line(seen: true, words: 1, cues: 0, live: "Paused") == "The prompter is paused.")
        #expect(PrompterAsk.line(seen: true, words: 1, cues: 0, live: "Holding") == "The prompter is holding.")
        #expect(PrompterAsk.line(seen: true, words: 1, cues: 0, live: "Waiting for you") == "The prompter is waiting for you.")
        #expect(PrompterAsk.line(seen: true, words: 1, cues: 0, live: "Get ready") == "Get ready.")
        #expect(PrompterAsk.line(seen: true, words: 1, cues: 0, live: "The end") == "The prompter is at the end.")
        #expect(PrompterAsk.matches("how's the prompter"))
        #expect(PrompterAsk.matches("Hey Zeus, how many words in my script?"))
        #expect(PrompterAsk.wantsCounts("how many cues"))
        #expect(!PrompterAsk.wantsCounts("how's the prompter"))
        #expect(!PrompterAsk.matches("how many words today"))
        #expect(!PrompterAsk.matches("how's my usage"))
        #expect(!PrompterAsk.matches("how much did I use today"))
        #expect(!PrompterAsk.matches("are my earbuds connected"))
    }
}
