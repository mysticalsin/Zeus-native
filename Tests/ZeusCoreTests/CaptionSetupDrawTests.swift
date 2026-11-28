import Testing
@testable import ZeusCore

struct CaptionSetupDrawTests {
    private func cards(_ plan: CaptionSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theOriginalAndSizeFollowCaption() {
        let usual = CaptionSetupDraw.plan(original: "On", size: "Medium")
        #expect(cards(usual) == ["Caption", "Original: On", "Size: Medium"])
        #expect(CaptionSetupAsk.line(original: "On", size: "Medium") == "The original is on, and the caption size is Medium.")
        #expect(usual.boltCaption(at: 0) == "Caption")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Size: Medium")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(CaptionSetupAsk.line(original: "Off", size: "Large") == "The original is off, and the caption size is Large.")
        #expect(cards(CaptionSetupDraw.plan(original: "On", size: "Small")) == ["Caption", "Original: On", "Size: Small"])
        #expect(cards(CaptionSetupDraw.plan(original: "On", size: "Huge")) == ["Caption", "Can't"])
        #expect(CaptionSetupAsk.line(original: "Maybe", size: "Medium") == "I can't read the captions.")
    }

    @Test func theLivePhaseAndTheSetupStayOffThisAsk() {
        #expect(CaptionSetupAsk.matches("how's captions set"))
        #expect(CaptionSetupAsk.matches("Hey Zeus, what's the caption size?"))
        #expect(CaptionSetupAsk.matches("caption settings"))
        #expect(!CaptionSetupAsk.matches("how's polyglot set"))
        #expect(!CaptionSetupAsk.matches("how's polyglot"))
        #expect(!CaptionSetupAsk.matches("how's beamer set"))
        #expect(!CaptionSetupAsk.matches("start live translation"))
    }
}
