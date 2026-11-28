import Testing
@testable import ZeusCore

struct RecordlyCaptureDrawTests {
    private func cards(_ plan: RecordlyCaptureDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshCaptureUsesTheDisplayWithoutSound() {
        let usual = RecordlyCaptureDraw.plan(source: "Display", sound: "Off")
        #expect(cards(usual) == ["Capture", "Source: Display", "Sound: Off"])
        #expect(RecordlyCaptureAsk.line(source: "Display", sound: "Off") == "Recordly captures a display, and system audio is off.")
        #expect(usual.boltCaption(at: 0) == "Capture")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Sound: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(RecordlyCaptureAsk.line(source: "Window", sound: "On") == "Recordly captures a window, and system audio is on.")
        #expect(RecordlyCaptureAsk.line(source: "Area", sound: "Off") == "Recordly captures an area, and system audio is off.")
        #expect(cards(RecordlyCaptureDraw.plan(source: "Screen", sound: "Off")) == ["Capture", "Can't"])
        #expect(RecordlyCaptureAsk.line(source: "Display", sound: "Maybe") == "I can't read what Recordly captures.")
    }

    @Test func aLiveRecordingStaysOffThisAsk() {
        #expect(RecordlyCaptureAsk.matches("what does recordly capture"))
        #expect(RecordlyCaptureAsk.matches("Hey Zeus, is Recordly system audio on?"))
        #expect(RecordlyCaptureAsk.matches("which recordly source"))
        #expect(!RecordlyCaptureAsk.matches("is recordly recording"))
        #expect(!RecordlyCaptureAsk.matches("how is recordly export set"))
        #expect(!RecordlyCaptureAsk.matches("how are routines set"))
        #expect(!RecordlyCaptureAsk.matches("how many screens"))
    }
}
