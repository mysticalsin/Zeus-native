import Testing
@testable import ZeusCore

struct VoiceOverDrawTests {
    @Test func voiceOverHoldingTheTalkKeysShowsShortcut() throws {
        let plan = try #require(VoiceOverDraw.from(line: "VoiceOver is using Control and Option. Record another shortcut in ZEUS Settings."))
        func cards(_ plan: VoiceOverDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["VoiceOver", "Shortcut"])
        #expect(plan.boltCaption(at: 0) == "VoiceOver")
        #expect(plan.boltCaption(at: 100) == "Shortcut")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aPointingHintAndOtherLinesAreNotThisCard() {
        #expect(VoiceOverDraw.from(line: "") == nil)
        #expect(VoiceOverDraw.from(line: "VoiceOver is using Control and Option. Choose another pointing key in Settings.") == nil)
        #expect(VoiceOverDraw.from(line: "That's a password or payment field, so I left it.") == nil)
        #expect(VoiceOverDraw.from(line: "That's it, you're done.") == nil)
    }
}
