import Testing
@testable import ZeusCore

struct MissingPieceDrawTests {
    @Test func aMissingPieceShowsItsName() throws {
        let plan = try #require(MissingPieceDraw.from(line: "Missing element index"))
        func cards(_ plan: MissingPieceDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Missing", "element index"])
        #expect(plan.boltCaption(at: 0) == "Missing")
        #expect(plan.boltCaption(at: 100) == "element index")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        let text = try #require(MissingPieceDraw.from(line: "Missing text"))
        #expect(cards(text) == ["Missing", "text"])
    }

    @Test func aPeriodAndAWrongFieldAreNotThisPiece() {
        #expect(MissingPieceDraw.from(line: "") == nil)
        #expect(MissingPieceDraw.from(line: "Missing") == nil)
        #expect(MissingPieceDraw.from(line: "Missing text.") == nil)
        #expect(MissingPieceDraw.from(line: "Element 3 isn't a text field.") == nil)
        #expect(MissingPieceDraw.from(line: "There's no element 3 on this page.") == nil)
        #expect(MissingPieceDraw.from(line: "No text field on this page") == nil)
        #expect(MissingPieceDraw.from(line: "No field called \"Search\"") == nil)
        #expect(MissingPieceDraw.from(line: "\"Red\" isn't one of the choices.") == nil)
    }
}
