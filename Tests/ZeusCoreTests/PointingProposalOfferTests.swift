import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing proposal offer")
struct PointingProposalOfferTests {
    private final class Sink: PointingActionSink {
        var inserts: [String] = []
        var clips: [String] = []
        func insertText(_ text: String) { inserts.append(text) }
        func writeClipboard(_ text: String) { clips.append(text) }
    }

    private let file = PointingProposalCandidate(id: "t3", isSecure: false, label: "File")

    @Test func aJavascriptLinkNeverReachesTheSink() {
        let sink = Sink()
        var tools = PointingActionTools()
        let decisions = PointingProposalGate.decide(
            [PointingProposalDraft(id: "p1", kind: "action", tool: "openURL", targetID: nil,
                                   arguments: ["url": "javascript:alert(1)"], summary: "Open the link")],
            candidates: [file], focusedFieldIsSecure: false, admittedThisTurn: 0)
        #expect(decisions == [.refused("url")])
        for decision in decisions {
            _ = tools.offer(decision, sink: sink)
        }
        #expect(sink.inserts.isEmpty)
        #expect(sink.clips.isEmpty)
        #expect(tools.phase == .idle)
    }

    @Test func anOrdinaryInsertReachesTheSinkOnce() {
        let sink = Sink()
        var tools = PointingActionTools()
        let decisions = PointingProposalGate.decide(
            [PointingProposalDraft(id: "p2", kind: "action", tool: "insertText", targetID: "t3",
                                   arguments: ["text": "hello"], summary: "Type hello")],
            candidates: [file], focusedFieldIsSecure: false, admittedThisTurn: 0)
        guard case .proceed(let proposal, _) = decisions.first else {
            Issue.record("the insert was not admitted")
            return
        }
        #expect(proposal.tool == .insertText)
        let phase = tools.offer(decisions[0], sink: sink)
        #expect(sink.inserts == ["hello"])
        #expect(sink.clips.isEmpty)
        if case .indicated(let indicator) = phase {
            #expect(indicator.summary == "Type hello")
        } else {
            Issue.record("the insert did not finish")
        }
    }
}
