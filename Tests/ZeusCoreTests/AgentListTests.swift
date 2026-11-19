import Testing
@testable import ZeusCore

@Suite("Agent list")
struct AgentListTests {
    @Test func aRowNamesTheStateAndDoesNotOpenATerminal() {
        #expect(AgentList.word(.working) == "Working")
        #expect(AgentList.word(.needsYou) == "Waiting for you")
        #expect(AgentList.word(.done) == "Done")
        #expect(AgentList.word(.failed) == "Error")
        #expect(AgentList.rowOpensDetails)
        #expect(!AgentList.rowJumpsToTerminal)
        #expect(AgentList.voice("Harbor", project: "Desk", status: .working, activity: "Reading the log")
            .contains("Working"))
    }
}
