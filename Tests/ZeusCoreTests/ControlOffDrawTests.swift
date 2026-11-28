import Testing
@testable import ZeusCore

struct ControlOffDrawTests {
    @Test func bothRefusalsShowControlOff() throws {
        let blocked = "I didn't run that action. Command-line control is off. Turn on 'Allow command-line control' in Settings."
        let restricted = "Screen capture and actions aren't allowed from the command line. Turn on 'Allow command-line control' in Settings."
        let plan = try #require(ControlOffDraw.from(line: blocked))
        let other = try #require(ControlOffDraw.from(line: restricted))
        func cards(_ plan: ControlOffDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Control", "Off"])
        #expect(cards(other) == ["Control", "Off"])
        #expect(plan.boltCaption(at: 0) == "Control")
        #expect(plan.boltCaption(at: 100) == "Off")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func otherSentencesAreNotControlOff() {
        #expect(ControlOffDraw.from(line: "") == nil)
        #expect(ControlOffDraw.from(line: "Safari didn't open.") == nil)
        #expect(ControlOffDraw.from(line: "One moment.") == nil)
        #expect(ControlOffDraw.from(line: "Command-line control is off.") == nil)
    }
}
