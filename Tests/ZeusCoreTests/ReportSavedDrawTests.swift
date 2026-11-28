import Testing
@testable import ZeusCore

struct ReportSavedDrawTests {
    @Test func aSavedReportShowsSaved() throws {
        let plan = try #require(ReportSavedDraw.from(line: "Done. The report is saved."))
        func cards(_ plan: ReportSavedDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Report", "Saved"])
        #expect(plan.boltCaption(at: 0) == "Report")
        #expect(plan.boltCaption(at: 100) == "Saved")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aMissingSaveAndOtherLinesAreNotSaved() {
        #expect(ReportSavedDraw.from(line: "") == nil)
        #expect(ReportSavedDraw.from(line: "Done. The report is saved. I couldn't save the report.") == nil)
        #expect(ReportSavedDraw.from(line: "What should I look into?") == nil)
        #expect(ReportSavedDraw.from(line: "VoiceOver is using Control and Option. Record another shortcut in ZEUS Settings.") == nil)
    }
}
