import Testing
@testable import ZeusCore

@Suite("STT voice.log flush")
struct STTFlushLinesTests {
    @Test func aCancelledOpenStillFlushesBothTipLines() {
        let lines = STTFlushLines.details(
            generation: 3, cancelled: true, path: STTFlushLines.murmurTap,
            deliveredToUI: "80", failure: "aborted", attempts: 1, failedTurns: 1)
        #expect(lines?.map(\.stage) == ["stt-latency", "stt-failure"])
        #expect(lines?[0].detail == "path=murmur-tap key_down=0 | capture: capture_start=- | vad: speech_start=- silence_detected=- endpoint_fired=- | asr: model_ready=- first_partial=- final_transcript=- | delivery: delivered_to_ui=80 | failure=aborted")
        #expect(lines?[1].detail == "failure_rate path=murmur-tap attempts=1 failed_turns=1 rate=1.000")
        #expect(lines?.allSatisfy { !$0.detail.contains("\n") && !$0.stage.contains("\n") } == true)
    }

    @Test func generationZeroWritesNothing() {
        let lines = STTFlushLines.details(
            generation: 0, cancelled: false, path: STTFlushLines.talkHold,
            failure: "none", attempts: 0, failedTurns: 0)
        #expect(lines == nil)
    }

    @Test func aWarmTalkLineUsesTheTipFields() {
        let lines = STTFlushLines.details(
            generation: 1, cancelled: false, path: STTFlushLines.talkHold,
            captureStart: "15", speechStart: "40", silenceDetected: "-", endpointFired: "600",
            modelReady: "0", firstPartial: "40", finalTranscript: "1050", deliveredToUI: "1100",
            failure: STTFlushLines.failureWord(cancelled: false, textLanded: true),
            attempts: 4, failedTurns: 0)
        #expect(lines?[0].detail == "path=talk-hold key_down=0 | capture: capture_start=15 | vad: speech_start=40 silence_detected=- endpoint_fired=600 | asr: model_ready=0 first_partial=40 final_transcript=1050 | delivery: delivered_to_ui=1100 | failure=none")
        #expect(lines?[1].detail == "failure_rate path=talk-hold attempts=4 failed_turns=0 rate=0.000")
    }

    @Test func anEmptyAppleTurnIsNoTextAndACancelIsAborted() {
        #expect(STTFlushLines.failureWord(cancelled: true, textLanded: true) == "aborted")
        #expect(STTFlushLines.failureWord(cancelled: false, textLanded: false) == "no_text")
        #expect(STTFlushLines.failureWord(cancelled: false, textLanded: true) == "none")
    }
}
