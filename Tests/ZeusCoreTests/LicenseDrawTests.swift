import Testing
@testable import ZeusCore

struct LicenseDrawTests {
    private func cards(_ plan: LicenseDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func thePageTitleIsTheSecondCard() {
        let yours = LicenseDraw.plan(word: "Zeus is yours.")
        #expect(cards(yours) == ["License", "Zeus is yours."])
        #expect(LicenseAsk.line(word: "Zeus is yours.") == "Zeus is yours.")
        #expect(yours.boltCaption(at: 0) == "License")
        #expect(yours.boltCaption(at: ExplainBeatSchedule.gap) == "Zeus is yours.")
        #expect(yours.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        let trial = "Trial \u{00B7} 12 days left"
        #expect(cards(LicenseDraw.plan(word: trial)) == ["License", trial])
        #expect(LicenseAsk.line(word: trial) == "The trial has 12 days left.")
        #expect(LicenseAsk.line(word: "Zeus is yours \u{00B7} 3 days left") == "Zeus is yours, with 3 days left.")
        #expect(LicenseAsk.line(word: "This license was turned off.") == "This license was turned off.")
        #expect(cards(LicenseDraw.plan(word: "Trial \u{00B7} 1 days left")) == ["License", "Can't"])
        #expect(cards(LicenseDraw.plan(word: "KEY-123")) == ["License", "Can't"])
        #expect(LicenseAsk.line(word: "") == "I can't read the license.")
    }

    @Test func theVoiceAndTheKeyboardStayOffThisAsk() {
        #expect(LicenseAsk.matches("how's my license"))
        #expect(LicenseAsk.matches("Hey Zeus, is Zeus licensed?"))
        #expect(LicenseAsk.matches("is the trial on"))
        #expect(!LicenseAsk.matches("which voice is this"))
        #expect(!LicenseAsk.matches("where's my keyboard"))
        #expect(!LicenseAsk.matches("how's face presence"))
        #expect(!LicenseAsk.matches("is hey zeus on"))
    }
}
