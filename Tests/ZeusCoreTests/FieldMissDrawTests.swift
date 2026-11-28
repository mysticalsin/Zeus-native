import Testing
@testable import ZeusCore

struct FieldMissDrawTests {
    @Test func aMissingNamedFieldShowsItsName() throws {
        let plan = try #require(FieldMissDraw.from(line: "No field called \"Search\""))
        func cards(_ plan: FieldMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Field", "Search"])
        #expect(plan.boltCaption(at: 0) == "Field")
        #expect(plan.boltCaption(at: 100) == "Search")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aPageWithNoFieldAndAMissingPieceAreNotThisName() {
        #expect(FieldMissDraw.from(line: "") == nil)
        #expect(FieldMissDraw.from(line: "No field called \"\"") == nil)
        #expect(FieldMissDraw.from(line: "No field called Search") == nil)
        #expect(FieldMissDraw.from(line: "No field called \"Search\".") == nil)
        #expect(FieldMissDraw.from(line: "No text field on this page") == nil)
        #expect(FieldMissDraw.from(line: "Element 3 isn't a text field.") == nil)
        #expect(FieldMissDraw.from(line: "Missing text") == nil)
        #expect(FieldMissDraw.from(line: "Okay, I didn't type anything.") == nil)
    }
}
