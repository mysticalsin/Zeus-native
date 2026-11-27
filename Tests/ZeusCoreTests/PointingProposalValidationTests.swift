import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing proposal validation")
struct PointingProposalValidationTests {
    private let share = PointingProposalCandidate(id: "t0", isSecure: false, label: "Share")
    private let file = PointingProposalCandidate(id: "t3", isSecure: false, label: "File")
    private let password = PointingProposalCandidate(id: "t4", isSecure: true, label: "Password")
    private let apiKey = PointingProposalCandidate(id: "t5", isSecure: false, label: "API key")
    private let delete = PointingProposalCandidate(id: "t6", isSecure: false, label: "Delete")

    private var candidates: [PointingProposalCandidate] { [share, file, password, apiKey, delete] }

    private func draft(
        _ id: String = "p0",
        kind: String,
        tool: String,
        target: String? = nil,
        arguments: [String: String] = [:],
        summary: String = "Wait for your click on File"
    ) -> PointingProposalDraft {
        PointingProposalDraft(id: id, kind: kind, tool: tool, targetID: target, arguments: arguments, summary: summary)
    }

    private func decide(
        _ proposals: [PointingProposalDraft],
        admitted: Int = 0,
        focusedSecure: Bool = false
    ) -> [PointingProposalDecision] {
        PointingProposalGate.decide(
            proposals, candidates: candidates, focusedFieldIsSecure: focusedSecure, admittedThisTurn: admitted
        )
    }

    private func proposal(
        _ id: String = "p0",
        kind: PointingProposal.Kind,
        tool: PointingProposal.Tool,
        target: String? = nil,
        arguments: [String: String] = [:],
        summary: String = "Wait for your click on File"
    ) -> PointingProposal {
        PointingProposal(id: id, kind: kind, tool: tool, targetID: target, arguments: arguments, summary: summary)
    }

    @Test func aClickOnFileIsGuidance() throws {
        let loaded = try fixtureClick()
        let decision = decide([loaded])
        #expect(decision == [.guide(proposal(kind: .guidance, tool: .awaitClick, target: "t3"))])
    }

    @Test func javascriptFileAndHttpLinksAreRefused() {
        let javascript = draft("p1", kind: "action", tool: "openURL", arguments: ["url": "javascript:alert(1)"], summary: "Open the link")
        let fileURL = draft("p2", kind: "action", tool: "openURL", arguments: ["url": "file:///etc/passwd"], summary: "Open the link")
        let http = draft("p3", kind: "action", tool: "openURL", arguments: ["url": "http://example.com"], summary: "Open the link")
        #expect(decide([javascript]) == [.refused("url")])
        #expect(decide([fileURL]) == [.refused("url")])
        #expect(decide([http]) == [.refused("url")])
    }

    @Test func anHttpsLinkAsksForTheHost() throws {
        let raw = "https://example.com/export"
        let decision = decide([draft("p1", kind: "action", tool: "openURL", arguments: ["url": raw], summary: "Open the link")])
        let admitted = proposal("p1", kind: .action, tool: .openURL, arguments: ["url": raw], summary: "Open the link")
        #expect(decision == [.askHost(admitted, host: "example.com")])
        let userinfo = draft("p2", kind: "action", tool: "openURL", arguments: ["url": "https://user:pass@example.com"], summary: "Open the link")
        #expect(decide([userinfo]) == [.refused("url")])
    }

    @Test func theFixtureJavascriptLinkIsRefused() throws {
        let loaded = try fixtureJavascript()
        #expect(decide([loaded]) == [.refused("url")])
    }

    @Test func aClipboardWriteConfirmsAtTheDriveRisk() {
        let text = "Quarterly-report.pdf"
        let decision = decide([draft("p1", kind: "action", tool: "clipboardWrite", arguments: ["text": text], summary: "Copy a suggested file name")])
        let admitted = proposal("p1", kind: .action, tool: .clipboardWrite, arguments: ["text": text], summary: "Copy a suggested file name")
        #expect(decision == [.confirm(admitted, DriveStep.writeClipboard(text).risk)])
        #expect(DriveStep.writeClipboard(text).risk == .destructive)
    }

    @Test func openingAnAppProceedsAtTheDriveRisk() {
        let bundle = "com.apple.Preview"
        let decision = decide([draft("p1", kind: "action", tool: "openApp", arguments: ["bundleID": bundle], summary: "Open Preview")])
        let admitted = proposal("p1", kind: .action, tool: .openApp, arguments: ["bundleID": bundle], summary: "Open Preview")
        #expect(decision == [.proceed(admitted, DriveStep.openApp(bundle).risk)])
        #expect(decide([draft("p2", kind: "action", tool: "openApp", arguments: ["bundleID": "../Preview"], summary: "Open Preview")]) == [.refused("bundle")])
    }

    @Test func ordinaryTextProceedsAndASecretOrReturnIsRefused() {
        let notes = "Notes"
        let into = DriveTarget(label: "Share")
        let decision = decide([draft("p1", kind: "action", tool: "insertText", target: "t0", arguments: ["text": notes], summary: "Type the name")])
        let admitted = proposal("p1", kind: .action, tool: .insertText, target: "t0", arguments: ["text": notes], summary: "Type the name")
        #expect(decision == [.proceed(admitted, DriveStep.type(notes, into: into).risk)])

        let secret = draft("p2", kind: "action", tool: "insertText", target: "t0", arguments: ["text": "the password is hidden"], summary: "Type the name")
        #expect(decide([secret]) == [.refused("secret")])
        let labeled = draft("p3", kind: "action", tool: "insertText", target: "t5", arguments: ["text": notes], summary: "Type the name")
        #expect(decide([labeled]) == [.refused("secret")])
        let secure = draft("p4", kind: "action", tool: "insertText", target: "t4", arguments: ["text": notes], summary: "Type the name")
        #expect(decide([secure]) == [.refused("secure")])
        let focused = draft("p5", kind: "action", tool: "insertText", arguments: ["text": notes], summary: "Type the name")
        #expect(decide([focused], focusedSecure: true) == [.refused("secure")])
        let line = draft("p6", kind: "action", tool: "insertText", target: "t0", arguments: ["text": "Notes\n"], summary: "Type the name")
        #expect(decide([line]) == [.refused("return")])
    }

    @Test func sendAndDeleteAskBeforeTheyRun() {
        let send = "Send the file"
        let decision = decide([draft("p1", kind: "action", tool: "insertText", target: "t0", arguments: ["text": send], summary: "Type the name")])
        let admitted = proposal("p1", kind: .action, tool: .insertText, target: "t0", arguments: ["text": send], summary: "Type the name")
        #expect(decision == [.confirm(admitted, .destructive)])
        let onDelete = draft("p2", kind: "action", tool: "insertText", target: "t6", arguments: ["text": "Notes"], summary: "Type the name")
        let deleteProposal = proposal("p2", kind: .action, tool: .insertText, target: "t6", arguments: ["text": "Notes"], summary: "Type the name")
        #expect(decide([onDelete]) == [.confirm(deleteProposal, .destructive)])
    }

    @Test func anUnknownToolKindOrExtraArgumentIsRefused() {
        #expect(decide([draft("p1", kind: "action", tool: "shell", summary: "Run it")]) == [.refused("tool")])
        #expect(decide([draft("p2", kind: "script", tool: "openApp", summary: "Run it")]) == [.refused("kind")])
        #expect(decide([draft("p3", kind: "guidance", tool: "openURL", arguments: ["url": "https://example.com"], summary: "Open the link")]) == [.refused("pairing")])
        let extra = draft("p4", kind: "action", tool: "openApp", arguments: ["bundleID": "com.apple.Preview", "command": "rm"], summary: "Open Preview")
        #expect(decide([extra]) == [.refused("arguments")])
    }

    @Test func aClickNeedsAKnownTargetAndAScrollCanWaitWithoutOne() {
        #expect(decide([draft(kind: "guidance", tool: "awaitClick")]) == [.refused("target")])
        #expect(decide([draft(kind: "guidance", tool: "awaitClick", target: "t9")]) == [.refused("target")])
        let scroll = draft("p1", kind: "guidance", tool: "awaitScroll", summary: "Scroll the page")
        #expect(decide([scroll]) == [.guide(proposal("p1", kind: .guidance, tool: .awaitScroll, summary: "Scroll the page"))])
    }

    @Test func threeProposalsInOneEventAreRefused() {
        let clicks = (0..<3).map { draft("p\($0)", kind: "guidance", tool: "awaitClick", target: "t3") }
        #expect(decide(clicks) == [.refused("event limit"), .refused("event limit"), .refused("event limit")])
    }

    @Test func theFourthAdmittedProposalOfTheTurnIsKeptAndTheFifthIsRefused() {
        let first = draft("p0", kind: "guidance", tool: "awaitClick", target: "t3")
        let second = draft("p1", kind: "guidance", tool: "awaitScroll", summary: "Scroll the page")
        let decisions = decide([first, second], admitted: 3)
        #expect(decisions[0] == .guide(proposal(kind: .guidance, tool: .awaitClick, target: "t3")))
        #expect(decisions[1] == .refused("turn limit"))
    }

    @Test func aRepeatedIdentifierIsRefused() {
        let first = draft("p0", kind: "guidance", tool: "awaitClick", target: "t3")
        let second = draft("p0", kind: "guidance", tool: "awaitScroll", summary: "Scroll the page")
        let decisions = decide([first, second])
        #expect(decisions[0] == .guide(proposal(kind: .guidance, tool: .awaitClick, target: "t3")))
        #expect(decisions[1] == .refused("identifier"))
    }

    @Test func aSummaryPastTwoHundredBytesIsRefused() {
        let summary = String(repeating: "a", count: 201)
        #expect(decide([draft(kind: "guidance", tool: "awaitClick", target: "t3", summary: summary)]) == [.refused("summary")])
    }

    private func fixtureClick() throws -> PointingProposalDraft {
        draft("p0", kind: "guidance", tool: "awaitClick", target: "t3", summary: "Wait for your click on File")
    }

    private func fixtureJavascript() throws -> PointingProposalDraft {
        draft("p1", kind: "action", tool: "openURL", arguments: ["url": "javascript:alert(1)"], summary: "Open the link")
    }
}
