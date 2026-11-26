import Foundation
import Testing
@testable import ZeusCore

private func json(_ text: String) -> JSONValue {
    try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

@Suite("Hub approval impact")
struct HubApprovalImpactTests {
    @Test func thePreviewNamesFilesDeletesHostsInstallsForcePushAndSecretPathsBeforeAllow() {
        let command = "rm -rf dist && curl https://example.com/pkg.tgz -o out.tgz && npm install left-pad && git push --force origin main && cp notes.txt .env"
        let impact = HubApprovalImpact.preview(tool: "Bash", command: command, input: nil)
        #expect(impact.files == ["out.tgz", "notes.txt", ".env"])
        #expect(impact.deletes == ["dist"])
        #expect(impact.hosts == ["example.com"])
        #expect(impact.installs == ["left-pad"])
        #expect(impact.forcePush == ["origin main"])
        #expect(impact.secretPaths == [".env"])
        #expect(impact.lines(detailsHidden: false).map(\.title) == [
            "Files", "Deletes", "Hosts", "Installs", "Force-push", "Secret paths",
        ])
        let spoken = impact.accessibilitySummary(detailsHidden: false)
        #expect(spoken.hasPrefix("Before allow. "))
        #expect(spoken.contains(".env"))
        #expect(spoken.contains("Approve") == false)
        #expect(HubApprovalImpact.allowOnceTitle == "Allow once")
        #expect(HubApprovalImpact.allowOnceTitle != "Approve")
    }

    @Test func hiddenDetailsLeaveThePathsUnsaid() {
        let impact = HubApprovalImpact.preview(tool: "Bash", command: "rm .env", input: nil)
        #expect(impact.deletes == [".env"])
        #expect(impact.secretPaths == [".env"])
        #expect(impact.lines(detailsHidden: true) == [HubApprovalImpact.Line(title: "Details hidden", detail: "")])
        #expect(impact.accessibilitySummary(detailsHidden: true) == "Details hidden")
        #expect(impact.accessibilitySummary(detailsHidden: true).contains(".env") == false)
    }

    @Test func aPlainListingShowsNothingBeforeAllow() {
        let impact = HubApprovalImpact.preview(tool: "Bash", command: "ls", input: nil)
        #expect(impact.isEmpty)
        #expect(impact.lines(detailsHidden: false).isEmpty)
        #expect(impact.lines(detailsHidden: true).isEmpty)
        #expect(impact.accessibilitySummary(detailsHidden: false).isEmpty)
    }

    @Test func anOrdinaryPushIsNotAForcePush() {
        let impact = HubApprovalImpact.preview(tool: "Bash", command: "git push origin main", input: nil)
        #expect(impact.forcePush.isEmpty)
        #expect(impact.deletes.isEmpty)
    }

    @Test func anEditNamesTheFileAndASecretPath() {
        let impact = HubApprovalImpact.preview(
            tool: "Edit",
            command: "Edit key",
            input: json(#"{"file_path":".ssh/id_ed25519"}"#)
        )
        #expect(impact.files == [".ssh/id_ed25519"])
        #expect(impact.secretPaths == [".ssh/id_ed25519"])
        #expect(impact.accessibilitySummary(detailsHidden: false).contains("id_ed25519"))
    }

    @Test func theFullCommandIsReadWhenTheCardLineIsCut() {
        let input = json(#"{"command":"git push --force origin main"}"#)
        let impact = HubApprovalImpact.preview(tool: "Bash", command: "git push", input: input)
        #expect(impact.forcePush == ["origin main"])
    }

    @Test func theRowMatchesTheSessionByIdOrByProjectName() {
        #expect(HubApprovalImpact.matchesSession(
            approvalSession: "s1", approvalAgent: "Claude", approvalProject: "zeus",
            sessionID: "s1", sessionAgent: "Other", sessionProject: "other"
        ))
        #expect(HubApprovalImpact.matchesSession(
            approvalSession: "s1", approvalAgent: "Claude", approvalProject: "zeus",
            sessionID: "s2", sessionAgent: "Claude", sessionProject: "zeus"
        ) == false)
        #expect(HubApprovalImpact.matchesSession(
            approvalSession: nil, approvalAgent: "Claude", approvalProject: "/repo/zeus",
            sessionID: "s2", sessionAgent: "Claude", sessionProject: "zeus"
        ))
        #expect(HubApprovalImpact.matchesSession(
            approvalSession: nil, approvalAgent: "Claude", approvalProject: "zeus",
            sessionID: "s2", sessionAgent: "Codex", sessionProject: "zeus"
        ) == false)
    }

    @Test func theHubRowShowsImpactBeforeAllowOnceAndDoesNotCallTheControlApprove() throws {
        let row = try source("Sources/Zeus/Agents/Hub/HubDecisionImpactRow.swift")
        let impact = try #require(row.range(of: "hub.decision.impact"))
        let allow = try #require(row.range(of: "hub.decision.allow-once"))
        #expect(impact.lowerBound < allow.lowerBound)
        #expect(row.contains("hub.decision.row"))
        #expect(row.contains("HubApprovalImpact.allowOnceTitle"))
        #expect(row.contains("Approve") == false)
        #expect(row.contains("LinearGradient") == false)
        #expect(row.contains("Color.black") == false)
        let page = try source("Sources/Zeus/TopBar/ChatPage.swift")
        let placed = try #require(page.range(of: "HubDecisionImpactRow"))
        let reply = try #require(page.range(of: "Reply to"))
        #expect(placed.lowerBound < reply.lowerBound)
        #expect(page.contains("accessibilityLabel(\"Approve\")") == false)
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}
