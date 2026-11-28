import Testing
@testable import ZeusCore

struct FlingPeerDrawTests {
    private func cards(_ plan: FlingPeerDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallUsesThisMacsNameAndHasNoPairs() {
        let usual = FlingPeerDraw.plan(name: "None", macs: "0")
        #expect(cards(usual) == ["Peers", "Name: None", "Macs: 0"])
        #expect(FlingPeerAsk.line(name: "None", macs: "0") == "Nearby Macs see this Mac's own name, and no Macs are paired.")
        #expect(usual.boltCaption(at: 0) == "Peers")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Macs: 0")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(FlingPeerAsk.line(name: "Chosen", macs: "1") == "A name is set for nearby Macs, and 1 Mac is paired.")
        #expect(FlingPeerAsk.line(name: "Chosen", macs: "3") == "A name is set for nearby Macs, and 3 Macs are paired.")
        #expect(cards(FlingPeerDraw.plan(name: "Zeus", macs: "0")) == ["Peers", "Can't"])
        #expect(FlingPeerAsk.line(name: "None", macs: "00") == "I can't read the paired Macs.")
    }

    @Test func theFlingSwitchStaysOffThisAsk() {
        #expect(FlingPeerAsk.matches("what name do nearby macs see"))
        #expect(FlingPeerAsk.matches("Hey Zeus, how many macs are paired?"))
        #expect(FlingPeerAsk.matches("which macs are paired"))
        #expect(!FlingPeerAsk.matches("how is fling set"))
        #expect(!FlingPeerAsk.matches("how is receiving set"))
        #expect(!FlingPeerAsk.matches("which flick sensitivity"))
        #expect(!FlingPeerAsk.matches("which cloud voices"))
    }
}
