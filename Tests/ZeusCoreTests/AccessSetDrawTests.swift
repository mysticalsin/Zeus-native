import Testing
@testable import ZeusCore

struct AccessSetDrawTests {
    private func cards(_ plan: AccessSetDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func micSpeechAndCameraFollowAllow() {
        let usual = AccessSetDraw.plan(mic: "Allowed", speech: "Not asked yet", camera: "Denied")
        #expect(cards(usual) == ["Allow", "Mic: Allowed", "Speech: Not asked yet", "Camera: Denied"])
        #expect(AccessSetAsk.line(mic: "Allowed", speech: "Not asked yet", camera: "Denied") == "The microphone is allowed, speech recognition has not been asked yet, and the camera is denied.")
        #expect(usual.boltCaption(at: 0) == "Allow")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Camera: Denied")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(AccessSetAsk.line(mic: "Denied", speech: "Allowed", camera: "Not asked yet") == "The microphone is denied, speech recognition is allowed, and the camera has not been asked yet.")
        #expect(cards(AccessSetDraw.plan(mic: "Not asked yet", speech: "Not asked yet", camera: "Allowed")) == ["Allow", "Mic: Not asked yet", "Speech: Not asked yet", "Camera: Allowed"])
        #expect(cards(AccessSetDraw.plan(mic: "On", speech: "Allowed", camera: "Denied")) == ["Allow", "Can't"])
        #expect(AccessSetAsk.line(mic: "Allowed", speech: "Maybe", camera: "Denied") == "I can't read those permissions.")
    }

    @Test func screenRecordingStaysOffThisAsk() {
        #expect(AccessSetAsk.matches("which voice permissions"))
        #expect(AccessSetAsk.matches("Hey Zeus, is the camera allowed?"))
        #expect(AccessSetAsk.matches("voice permission settings"))
        #expect(!AccessSetAsk.matches("is screen recording on"))
        #expect(!AccessSetAsk.matches("can you see the screen"))
        #expect(!AccessSetAsk.matches("how's speaker recognition set"))
        #expect(!AccessSetAsk.matches("how's face presence set"))
    }
}
