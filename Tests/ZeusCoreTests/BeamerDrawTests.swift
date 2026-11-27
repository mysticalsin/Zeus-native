import Testing
@testable import ZeusCore

struct BeamerDrawTests {
    @Test func commandsAndAMachineNameBeamer() throws {
        let start = try #require(BeamerDraw.from(summary: "Start Beamer"))
        let pause = try #require(BeamerDraw.from(summary: "Pause Beamer"))
        let back = try #require(BeamerDraw.from(summary: "Input back to this Mac"))
        let machine = try #require(BeamerDraw.from(summary: "Switch to MacBook"))
        let ipad = try #require(BeamerDraw.from(summary: "iPad"))
        func cards(_ plan: BeamerDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(start) == ["Beamer", "Start"])
        #expect(cards(try #require(BeamerDraw.from(summary: "Open Beamer"))) == ["Beamer", "Open"])
        #expect(cards(pause) == ["Beamer", "Pause"])
        #expect(cards(try #require(BeamerDraw.from(summary: "Resume Beamer"))) == ["Beamer", "Resume"])
        #expect(cards(back) == ["Beamer", "This Mac"])
        #expect(cards(machine) == ["Beamer", "MacBook"])
        #expect(cards(ipad) == ["Beamer", "Not paired"])
        #expect(machine.boltCaption(at: 0) == "Beamer")
        #expect(machine.boltCaption(at: 100) == "MacBook")
        #expect(machine.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(machine.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(ipad.boltCaption(at: 100) == "Not paired")
    }

    @Test func aBlankMachineAndOtherSummariesAreNotDrawn() {
        #expect(BeamerDraw.from(summary: "Switch to ") == nil)
        #expect(BeamerDraw.from(summary: "Switch to   ") == nil)
        #expect(BeamerDraw.plan(detail: " ") == nil)
        #expect(BeamerDraw.from(summary: "Open Safari") == nil)
        #expect(BeamerDraw.from(summary: "Play Spotify") == nil)
        #expect(BeamerDraw.from(summary: "Next track") == nil)
        #expect(BeamerDraw.from(summary: "Terminal") == nil)
    }
}
