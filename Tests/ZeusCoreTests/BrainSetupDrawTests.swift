import Testing
@testable import ZeusCore

struct BrainSetupDrawTests {
    private func cards(_ plan: BrainSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallHasNoVault() {
        let usual = BrainSetupDraw.plan(link: "None", access: "None")
        #expect(cards(usual) == ["Brain", "Link: None", "Access: None"])
        #expect(BrainSetupAsk.line(link: "None", access: "None") == "No vault is connected, and access is not set.")
        #expect(usual.boltCaption(at: 0) == "Brain")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Access: None")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(BrainSetupAsk.line(link: "Set", access: "Read") == "A vault is connected, and access is read only.")
        #expect(BrainSetupAsk.line(link: "Set", access: "Write") == "A vault is connected, and access is read and write.")
        #expect(cards(BrainSetupDraw.plan(link: "Documents", access: "None")) == ["Brain", "Can't"])
        #expect(BrainSetupAsk.line(link: "None", access: "Full") == "I can't read the second brain.")
    }

    @Test func toDoSettingsStayOffThisAsk() {
        #expect(BrainSetupAsk.matches("how is the second brain set"))
        #expect(BrainSetupAsk.matches("Hey Zeus, is a vault connected?"))
        #expect(BrainSetupAsk.matches("is the vault read only"))
        #expect(!BrainSetupAsk.matches("how are to-dos set"))
        #expect(!BrainSetupAsk.matches("what is the second talk key"))
        #expect(!BrainSetupAsk.matches("how is research set"))
    }
}
