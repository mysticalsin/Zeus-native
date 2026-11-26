import Testing
@testable import ZeusCore

@Suite("Dictation latency")
struct DictationLatencyTests {
    @Test func theLogIsDurationsOnly() {
        var trace = DictationLatency()
        trace.mark(.micHot, atMs: 12)
        trace.mark(.firstFrame, atMs: 40)
        trace.mark(.partial, atMs: 80)
        trace.mark(.finalTranscript, atMs: 210)
        trace.mark(.inserted, atMs: 228)
        trace.mark(.actionDone, atMs: 290)
        trace.mark(.micHot, atMs: 99)
        trace.mark(.firstFrame, atMs: -5)
        let line = trace.logLine
        #expect(line == "dictation-latency mic_hot=12 first_frame=40 partial=80 final=210 inserted=228 action=290")
        #expect(trace.milliseconds(.micHot) == 12)
        #expect(!line.contains("Spotify"))
        #expect(line.split(separator: " ").count == 7)
    }

    @Test func aMissingStageIsADash() {
        let line = DictationLatency().logLine
        #expect(line.contains("mic_hot=-"))
        #expect(line.contains("action=-"))
    }

    @Test func armingOnceThenTwoPressesBuildOneEngine() {
        var plan = ListeningEnginePlan()
        plan.arm()
        #expect(plan.press(formatValid: true) == false)
        #expect(plan.press(formatValid: true) == false)
        #expect(plan.builds == 1)
    }

    @Test func aBadFormatBuildsAgain() {
        var plan = ListeningEnginePlan()
        plan.arm()
        #expect(plan.press(formatValid: false))
        #expect(plan.builds == 2)
        #expect(plan.press(formatValid: true) == false)
        #expect(plan.builds == 2)
    }
}
