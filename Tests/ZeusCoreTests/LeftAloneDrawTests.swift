import Testing
@testable import ZeusCore

struct LeftAloneDrawTests {
    @Test func leavingItAloneNamesWhat() throws {
        let cases = [
            ("Okay, I won't start it.", "Start"),
            ("Okay, I won't run it.", "Run"),
            ("Okay, I won't touch anything.", "Drive"),
        ]
        for (line, what) in cases {
            let plan = try #require(LeftAloneDraw.from(line: line))
            func cards(_ plan: LeftAloneDraw) -> [String] {
                plan.draw.marks.compactMap { mark in
                    if case .card(_, let text) = mark.shape { return text }
                    return nil
                }
            }
            #expect(cards(plan) == ["Left", what])
            #expect(plan.boltCaption(at: 0) == "Left")
            #expect(plan.boltCaption(at: 100) == what)
            #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
            #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        }
    }

    @Test func aSpokenVerdictIsNotLeftAlone() {
        #expect(LeftAloneDraw.from(line: "") == nil)
        #expect(LeftAloneDraw.from(line: "Denied.") == nil)
        #expect(LeftAloneDraw.from(line: "Approved.") == nil)
        #expect(LeftAloneDraw.from(line: "Okay.") == nil)
        #expect(LeftAloneDraw.from(line: "I need Calendar access to add that.") == nil)
    }
}
