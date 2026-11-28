import Testing
@testable import ZeusCore

struct BeamerMissDrawTests {
    @Test func aBeamerZeusCouldNotUseShowsWhy() throws {
        let stopped = try #require(BeamerMissDraw.from(line: "Beamer isn't running. Say start Beamer first."))
        let gone = try #require(BeamerMissDraw.from(line: "Beamer isn't installed. Settings › Beamer can install it."))
        let home = try #require(BeamerMissDraw.from(line: "Beamer has nothing to bring back."))
        let quiet = try #require(BeamerMissDraw.from(line: "Beamer didn't answer."))
        func cards(_ plan: BeamerMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(stopped) == ["Beamer", "Not running"])
        #expect(stopped.boltCaption(at: 0) == "Beamer")
        #expect(stopped.boltCaption(at: 100) == "Not running")
        #expect(stopped.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(stopped.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(cards(gone) == ["Beamer", "Missing"])
        #expect(cards(home) == ["Beamer", "Nothing"])
        #expect(cards(quiet) == ["Beamer", "No reply"])
    }

    @Test func aBeamerCommandThatRanIsNotThisMiss() {
        #expect(BeamerMissDraw.from(line: "") == nil)
        #expect(BeamerMissDraw.from(line: "Pausing Beamer.") == nil)
        #expect(BeamerMissDraw.from(line: "Beamer didn't open.") == nil)
        #expect(BeamerMissDraw.from(line: "Beamer doesn't pair iPads. Use Universal Control for the iPad.") == nil)
        #expect(BeamerMissDraw.from(line: "the AI kept giving steps I couldn't use.") == nil)
    }
}
