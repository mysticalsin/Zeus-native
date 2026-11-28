import Testing
@testable import ZeusCore

struct VaultMissDrawTests {
    @Test func aVaultWithNoNotesShowsNone() throws {
        let plan = try #require(VaultMissDraw.from(line: "I looked in your vault and didn't find notes about tides."))
        func cards(_ plan: VaultMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Vault", "None"])
        #expect(plan.boltCaption(at: 0) == "Vault")
        #expect(plan.boltCaption(at: 100) == "None")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aFinishedToDoAndAFoundNoteAreNotThisVault() {
        #expect(VaultMissDraw.from(line: "") == nil)
        #expect(VaultMissDraw.from(line: "I looked in your vault and didn't find notes about .") == nil)
        #expect(VaultMissDraw.from(line: "Done: send the invoice.") == nil)
        #expect(VaultMissDraw.from(line: "I couldn't find a to-do called the invoice.") == nil)
        #expect(VaultMissDraw.from(line: "In notes.md: tides come in twice a day.") == nil)
        #expect(VaultMissDraw.from(line: "I couldn't find that.") == nil)
    }
}
