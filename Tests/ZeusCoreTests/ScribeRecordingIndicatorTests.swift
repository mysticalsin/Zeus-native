import Testing
@testable import ZeusCore

@Suite struct ScribeRecordingIndicatorTests {
    @Test func recordingAndEndingStayVisibleOnTheClosedNotch() {
        #expect(ScribeRecordingIndicator.feedback(for: "recording") == (phase: "recording", label: "Recording"))
        #expect(ScribeRecordingIndicator.feedback(for: "ending") == (phase: "recording", label: "Ending the recording"))
        #expect(ScribeRecordingIndicator.feedback(for: "idle") == nil)
    }
}
