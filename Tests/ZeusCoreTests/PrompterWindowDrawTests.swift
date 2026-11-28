import Testing
@testable import ZeusCore

struct PrompterWindowDrawTests {
    private func cards(_ plan: PrompterWindowDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theDimAndThePlace() {
        let usual = PrompterWindowDraw.plan(dim: "100", place: "Camera")
        #expect(cards(usual) == ["Window", "Dim: 100", "Place: Camera"])
        #expect(PrompterWindowAsk.line(dim: "100", place: "Camera") == "The prompter is at 100 percent, and it sits next to the camera.")
        #expect(usual.boltCaption(at: 0) == "Window")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Place: Camera")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(PrompterWindowAsk.line(dim: "70", place: "Chosen") == "The prompter is at 70 percent, and it sits on a display you chose.")
        #expect(PrompterWindowAsk.line(dim: "40", place: "Camera") == "The prompter is at 40 percent, and it sits next to the camera.")
        #expect(cards(PrompterWindowDraw.plan(dim: "20", place: "Camera")) == ["Window", "Can't"])
        #expect(PrompterWindowAsk.line(dim: "100", place: "Screen") == "I can't read the prompter window.")
    }

    @Test func theScriptControlsStayOffThisAsk() {
        #expect(PrompterWindowAsk.matches("how dim is the prompter"))
        #expect(PrompterWindowAsk.matches("Hey Zeus, where does the prompter show?"))
        #expect(PrompterWindowAsk.matches("is the prompter next to the camera"))
        #expect(!PrompterWindowAsk.matches("how is the prompter set"))
        #expect(!PrompterWindowAsk.matches("how is the prompter script set"))
        #expect(!PrompterWindowAsk.matches("how many macs are nearby"))
        #expect(!PrompterWindowAsk.matches("is fling looking"))
    }
}
