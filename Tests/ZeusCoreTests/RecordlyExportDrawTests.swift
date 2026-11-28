import Testing
@testable import ZeusCore

struct RecordlyExportDrawTests {
    private func cards(_ plan: RecordlyExportDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshExportUsesBothFormatsAt1080p() {
        let usual = RecordlyExportDraw.plan(format: "Both", size: "1080p", quality: "Balanced", follow: "On")
        #expect(cards(usual) == ["Export", "Format: Both", "Size: 1080p", "Quality: Balanced", "Cursor: On"])
        #expect(RecordlyExportAsk.line(format: "Both", size: "1080p", quality: "Balanced", follow: "On") == "Recordly exports both MP4 and GIF, at 1080p, in balanced quality, and follows the cursor while zoomed.")
        #expect(usual.boltCaption(at: 0) == "Export")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Cursor: On")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(RecordlyExportAsk.line(format: "GIF", size: "4K", quality: "Light", follow: "Off") == "Recordly exports GIF, at 4K, in light quality, and does not follow the cursor.")
        #expect(RecordlyExportAsk.line(format: "None", size: "1080p", quality: "High", follow: "On") == "Recordly exports nothing, at 1080p, in high quality, and follows the cursor while zoomed.")
        #expect(cards(RecordlyExportDraw.plan(format: "WebM", size: "1080p", quality: "Balanced", follow: "On")) == ["Export", "Can't"])
        #expect(RecordlyExportAsk.line(format: "MP4", size: "720p", quality: "Balanced", follow: "On") == "I can't read the Recordly export.")
    }

    @Test func aLiveRecordingStaysOffThisAsk() {
        #expect(RecordlyExportAsk.matches("how is recordly export set"))
        #expect(RecordlyExportAsk.matches("Hey Zeus, does Recordly follow the cursor?"))
        #expect(RecordlyExportAsk.matches("what is the recordly quality"))
        #expect(!RecordlyExportAsk.matches("is recordly recording"))
        #expect(!RecordlyExportAsk.matches("how is recording set"))
        #expect(!RecordlyExportAsk.matches("which other agents show in the notch"))
        #expect(!RecordlyExportAsk.matches("how many screens"))
    }
}
