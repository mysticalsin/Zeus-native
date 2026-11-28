import Testing
@testable import ZeusCore

struct PolyglotOffDrawTests {
    @Test func translationTurnedOffInSettingsShowsSettings() throws {
        let plan = try #require(PolyglotOffDraw.from(line: "Polyglot is turned off in Settings."))
        func cards(_ plan: PolyglotOffDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Translation", "Settings"])
        #expect(plan.boltCaption(at: 0) == "Translation")
        #expect(plan.boltCaption(at: 100) == "Settings")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aLiveTranslationAndAMissingFolderAreNotThisOff() {
        #expect(PolyglotOffDraw.from(line: "") == nil)
        #expect(PolyglotOffDraw.from(line: "Polyglot is off") == nil)
        #expect(PolyglotOffDraw.from(line: "Starting live translation.") == nil)
        #expect(PolyglotOffDraw.from(line: "Stopping live translation.") == nil)
        #expect(PolyglotOffDraw.from(line: "I can't find the folder Notes.") == nil)
        #expect(PolyglotOffDraw.from(line: "the browser agent is off. Turn it on in Settings.") == nil)
    }
}
