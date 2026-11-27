import Testing
@testable import ZeusCore

struct ReportMissDrawTests {
    @Test func aReportThatDidNotSaveShowsNotSaved() throws {
        let empty = try #require(ReportMissDraw.from(line: "Done. The report is saved. I couldn't save the report."))
        let tides = try #require(ReportMissDraw.from(line: "Tides. I couldn't save the report."))
        func cards(_ plan: ReportMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(empty) == ["Report", "Not saved"])
        #expect(empty.boltCaption(at: 0) == "Report")
        #expect(empty.boltCaption(at: 100) == "Not saved")
        #expect(empty.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(empty.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(cards(tides) == ["Report", "Not saved"])
    }

    @Test func aSavedReportAndASecretPointAreNotThisMiss() {
        #expect(ReportMissDraw.from(line: "") == nil)
        #expect(ReportMissDraw.from(line: "Done. The report is saved.") == nil)
        #expect(ReportMissDraw.from(line: "I couldn't save the report.") == nil)
        #expect(ReportMissDraw.from(line: "What should I look into?") == nil)
        #expect(ReportMissDraw.from(line: "I won't point at that.") == nil)
    }
}
