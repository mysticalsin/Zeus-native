import Testing
@testable import ZeusCore

struct HaloLightDrawTests {
    private func cards(_ plan: HaloLightDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func thePictureTitleIsTheSecondCard() {
        let classic = HaloLightDraw.plan(word: "Classic halo")
        #expect(cards(classic) == ["Light", "Classic halo"])
        #expect(HaloLightAsk.line(word: "Classic halo") == "The notch light is the Classic halo.")
        #expect(classic.boltCaption(at: 0) == "Light")
        #expect(classic.boltCaption(at: ExplainBeatSchedule.gap) == "Classic halo")
        #expect(classic.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(HaloLightAsk.line(word: "Off") == "The notch light is off.")
        #expect(HaloLightAsk.line(word: "Volumetric light") == "The notch light is Volumetric light.")
        #expect(cards(HaloLightDraw.plan(word: "Banana")) == ["Light", "Can't"])
        #expect(HaloLightAsk.line(word: "") == "I can't read the notch light.")
    }

    @Test func openingTheNotchStaysOffThisAsk() {
        #expect(HaloLightAsk.matches("what's the halo"))
        #expect(HaloLightAsk.matches("Hey Zeus, how's the halo?"))
        #expect(HaloLightAsk.matches("halo style"))
        #expect(!HaloLightAsk.matches("how does the notch open"))
        #expect(!HaloLightAsk.matches("how's the notch"))
        #expect(!HaloLightAsk.matches("what's the card style"))
        #expect(!HaloLightAsk.matches("when's zeus beside the pointer"))
    }
}
