import Testing
@testable import ZeusCore

struct PrompterRollDrawTests {
    private func cards(_ plan: PrompterRollDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theModeTheTypeAndTheSpeed() {
        let usual = PrompterRollDraw.plan(mode: "Follow my words", size: "32", speed: "40")
        #expect(cards(usual) == ["Script", "Mode: Follow my words", "Size: 32", "Speed: 40"])
        #expect(PrompterRollAsk.line(mode: "Follow my words", size: "32", speed: "40") == "The prompter follows your words, the type is 32, and the speed is 40.")
        #expect(usual.boltCaption(at: 0) == "Script")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Speed: 40")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(PrompterRollAsk.line(mode: "Scroll while I speak", size: "18", speed: "8") == "The prompter scrolls while you speak, the type is 18, and the speed is 8.")
        #expect(PrompterRollAsk.line(mode: "Steady speed", size: "72", speed: "120") == "The prompter uses a steady speed, the type is 72, and the speed is 120.")
        #expect(cards(PrompterRollDraw.plan(mode: "Follow my words", size: "17", speed: "40")) == ["Script", "Can't"])
        #expect(PrompterRollAsk.line(mode: "Steady speed", size: "32", speed: "121") == "I can't read the prompter script.")
    }

    @Test func thePrompterSwitchesStayOffThisAsk() {
        #expect(PrompterRollAsk.matches("how is the prompter script set"))
        #expect(PrompterRollAsk.matches("Hey Zeus, what is the prompter speed?"))
        #expect(PrompterRollAsk.matches("does the prompter follow my words"))
        #expect(!PrompterRollAsk.matches("how is the prompter set"))
        #expect(!PrompterRollAsk.matches("prompter settings"))
        #expect(!PrompterRollAsk.matches("what is the quick to-do key"))
        #expect(!PrompterRollAsk.matches("is focus running"))
    }
}
