import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Uses disposable app-owned records only. Does not start Scribe, capture, or open a vault.
@MainActor @Suite("Memory graph navigation")
struct WikiGraphNavigationTests {
    private func fixture() throws -> (URL, WikiStore, WikiController, String, String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-graph-navigation-\(UUID().uuidString)")
        let wiki = WikiStore(root: root.appendingPathComponent("wiki"))
        let meetings = ScribeMeetingStore(directory: root.appendingPathComponent("meetings"))
        let now = Date(timeIntervalSince1970: 1_000)
        let alpha = ScribeMeetingRecord(id: UUID(), title: "Project Alpha", endedAt: now, duration: 60,
            notes: ScribeMeetingNotes(decisions: ["A synthetic Alpha decision"]), transcript: [])
        let beta = ScribeMeetingRecord(id: UUID(), title: "Project Beta", endedAt: now, duration: 60,
            notes: ScribeMeetingNotes(decisions: ["A synthetic Beta decision"]), transcript: [])
        try meetings.save(alpha)
        try meetings.save(beta)
        let controller = WikiController(store: wiki, meetings: meetings, userName: { "Synthetic" }, clock: { now })
        controller.refreshFromMeetings(force: true)
        let origin = try #require(controller.pages.first(where: { $0.meetingIDs.contains(alpha.id) }))
        let target = try #require(controller.pages.first(where: { $0.meetingIDs.contains(beta.id) }))
        controller.select(origin.id)
        controller.setDraftBody(controller.draftBody + "\n[[\(target.id)]]")
        return (root, wiki, controller, origin.id, target.id)
    }

    @Test func editedLinkBecomesGraphNavigationAndSavesBeforeChangingPage() throws {
        let (root, wiki, controller, origin, target) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        controller.query = "A search hiding the target"
        controller.openGraph()
        #expect(controller.graphOpen)
        #expect(controller.graphSnapshot.edges.map(\.targetID) == [target])
        controller.graphRelationID = target
        controller.graphQuery = target
        controller.selectGraphPage(target)
        #expect(controller.selectedID == target)
        #expect(controller.query.isEmpty)
        #expect(controller.graphQuery.isEmpty)
        #expect(controller.graphRelationID == nil)
        #expect(controller.graphSnapshot.edges.first?.linkDirection == .incoming)
        #expect(wiki.loadPages().pages.first(where: { $0.id == origin })?.body.contains("[[\(target)]]") == true)
    }

    @Test func deletedTargetCannotBeReopenedFromAnOldGraphID() throws {
        let (root, _, controller, origin, target) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        controller.openGraph()
        controller.selectGraphPage(target)
        controller.confirmDelete()
        controller.select(origin)
        #expect(controller.graphSnapshot.edges.isEmpty)
        controller.selectGraphPage(target)
        #expect(controller.selectedID == origin)
        #expect(!controller.pages.contains(where: { $0.id == target }))
    }

    @Test func forgettingCurrentSourceRemovesTheFocusedGraphAndDurablyBlocksRelearning() throws {
        let (root, wiki, controller, origin, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        controller.openGraph()
        let source = try #require(controller.selectedPage?.meetingIDs.first)
        controller.forgetMeeting(source)
        controller.refreshFromMeetings(force: true)
        #expect(!controller.graphSnapshot.nodes.contains(where: { $0.id == origin }))
        #expect(wiki.loadStateRecovering().state.forgottenMeetings.contains(source))
        #expect(!controller.pages.contains(where: { $0.id == origin }))
    }

    @Test func unreadableMemorySettingsExposeNoGraphEvidence() throws {
        let (root, wiki, controller, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        controller.flushEdit()
        try "corrupt settings".write(to: wiki.stateURL, atomically: false, encoding: .utf8)
        controller.reload()
        controller.openGraph()
        #expect(controller.settingsUnreadable)
        #expect(controller.graphSnapshot.nodes.isEmpty)
        #expect(controller.graphSnapshot.edges.isEmpty)
    }
}
