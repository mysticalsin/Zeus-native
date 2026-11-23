import Testing
@testable import ZeusCore

@Suite struct DemoSpeechTests {
    /// Play Demo's menu-bar step is the first spoken line. A silent demo leaves the speaker with nothing.
    @Test func theMenuBarPointStepSpeaksALine() {
        var spoken: [String] = []
        let line = DemoSpeech.speak(.menuBarPoint) { spoken.append($0) }
        #expect(line == "that's me up here, click the bolt anytime")
        #expect(spoken == ["that's me up here, click the bolt anytime"])
    }
}
