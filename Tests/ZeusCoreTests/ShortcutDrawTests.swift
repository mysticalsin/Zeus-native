import Testing
@testable import ZeusCore

struct ShortcutDrawTests {
    @Test func aSavedPhraseShowsItsSteps() throws {
        let saved = try #require(ShortcutDraw.saved(phrase: "focus mode", steps: ["close Slack", "open Notes", "open Mail"]))
        let missed = try #require(ShortcutDraw.notSaved(phrase: "focus mode"))
        let replay = try #require(ShortcutDraw.done())
        func cards(_ plan: ShortcutDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(saved) == ["Shortcut", "focus mode", "close Slack", "open Notes"])
        #expect(saved.boltCaption(at: 0) == "Shortcut")
        #expect(saved.boltCaption(at: ExplainBeatSchedule.gap) == "focus mode")
        #expect(saved.boltCaption(at: 100) == "open Notes")
        #expect(saved.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(saved.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 230))
        #expect(cards(missed) == ["Shortcut", "focus mode", "Not saved"])
        #expect(missed.boltCaption(at: 100) == "Not saved")
        #expect(cards(replay) == ["Shortcut", "Done"])
        #expect(replay.boltCaption(at: 100) == "Done")
    }

    @Test func aBlankPhraseIsNotDrawn() {
        #expect(ShortcutDraw.saved(phrase: " ", steps: ["open Notes"]) == nil)
        #expect(ShortcutDraw.saved(phrase: "", steps: []) == nil)
        #expect(cards(ShortcutDraw.notSaved(phrase: " ")) == ["Shortcut", "Not saved"])
    }

    private func cards(_ plan: ShortcutDraw?) -> [String] {
        guard let plan else { return [] }
        return plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }
}
