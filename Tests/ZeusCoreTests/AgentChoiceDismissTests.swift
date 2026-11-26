import Foundation
import Testing
@testable import ZeusCore

@Suite("Agent choice dismiss")
struct AgentChoiceDismissTests {
    @Test func aZeusSelectClearsThePopup() {
        var card = AgentChoiceDismiss.shown(session: "s", tool: "AskUserQuestion")
        let closed = card.select(on: .zeus)
        #expect(closed)
        #expect(card.open == false)
        #expect(card.answeredOn == .zeus)
        let again = card.select(on: .peer, session: "s", tool: "AskUserQuestion")
        #expect(again == false)
        #expect(card.open == false)
        #expect(card.answeredOn == .zeus)
    }

    @Test func aPeerSelectClearsTheSameChoice() {
        var card = AgentChoiceDismiss.shown(session: "s", tool: "AskUserQuestion")
        let closed = card.select(on: .peer, session: "s", tool: "Question")
        #expect(closed)
        #expect(card.open == false)
        #expect(card.answeredOn == .peer)
        let again = card.select(on: .zeus)
        #expect(again == false)
        #expect(card.answeredOn == .peer)
    }

    @Test func anotherSessionsChoiceLeavesThisPopupUp() {
        var card = AgentChoiceDismiss.shown(session: "s", tool: "AskUserQuestion")
        let other = card.select(on: .peer, session: "other", tool: "AskUserQuestion")
        let otherTool = card.select(on: .peer, session: "s", tool: "Bash")
        #expect(other == false)
        #expect(otherTool == false)
        #expect(card.open)
        #expect(card.answeredOn == nil)
        #expect(PeerQuestionSelection.chose(detail: #"{"answers":{"Q":"A"}}"#))
        #expect(PeerQuestionSelection.chose(detail: #"{"answers":{"Q":"  "}}"#) == false)
        #expect(PeerQuestionSelection.chose(detail: "User has not answered yet") == false)
        #expect(PeerQuestionSelection.chose(detail: nil) == false)
    }
}
