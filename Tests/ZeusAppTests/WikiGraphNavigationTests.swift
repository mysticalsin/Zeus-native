import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Uses disposable app-owned records only. Does not start Scribe, capture, or open a vault.
@MainActor @Suite("Memory graph navigation")
struct WikiGraphNavigationTests {
    private func fixture(
        cancelledMeetingIDs: @escaping () -> Set<UUID> = { [] },
        navigateToMeeting: @escaping @MainActor (UUID) -> WikiMeetingNavigationOutcome = { _ in .unavailable },
        announce: @escaping (String) -> Void = { _ in }
    ) throws -> (URL, WikiStore, WikiController, String, String) {
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
        let controller = WikiController(store: wiki, meetings: meetings, userName: { "Synthetic" }, clock: { now },
            cancelledMeetingIDs: cancelledMeetingIDs, navigateToMeeting: navigateToMeeting, announce: announce)
        controller.refreshFromMeetings(force: true)
        let origin = try #require(controller.pages.first(where: { $0.meetingIDs.contains(alpha.id) }))
        let target = try #require(controller.pages.first(where: { $0.meetingIDs.contains(beta.id) }))
        controller.select(origin.id)
        controller.setDraftBody(controller.draftBody + "\n[[\(target.id)]]")
        return (root, wiki, controller, origin.id, target.id)
    }

    @Test func editedLinkBecomesGraphNavigationAndSavesBeforeChangingPage() throws {
        let (root, wiki, controller, origin, target) = try fixture()
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
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
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
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
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
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
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        controller.flushEdit()
        try "corrupt settings".write(to: wiki.stateURL, atomically: false, encoding: .utf8)
        controller.reload()
        controller.openGraph()
        #expect(controller.settingsUnreadable)
        #expect(controller.graphSnapshot.nodes.isEmpty)
        #expect(controller.graphSnapshot.edges.isEmpty)
    }

    @Test func resettingCombinedFiltersRestoresConnectionsWithoutChangingPageOrDraft() throws {
        let (root, _, controller, origin, target) = try fixture()
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        controller.openGraph()
        controller.graphShowsList = true
        controller.graphFilter = .sharedSources
        controller.graphQuery = "  no matching page  "
        controller.graphRelationID = target
        controller.query = "A separate sidebar search"
        let draft = controller.draftBody + "\nAn unsaved synthetic edit"
        controller.setDraftBody(draft)
        #expect(controller.hasGraphFilters)
        #expect(controller.graphFilterDescription == "Shared sources · Search: “no matching page”")
        #expect(controller.graphSnapshot.relationships.isEmpty)
        #expect(controller.graphSnapshot.totalRelationshipCount == 1)
        controller.resetGraphFilters()
        #expect(!controller.hasGraphFilters)
        #expect(controller.graphFilterDescription == "All connections")
        #expect(controller.graphSnapshot.relationships.map(\.pageID) == [target])
        #expect(controller.graphRelationID == nil)
        #expect(controller.selectedID == origin)
        #expect(controller.draftBody == draft)
        #expect(controller.query == "A separate sidebar search")
        #expect(controller.graphShowsList)
    }

    @Test func changingInjectedCancellationBlocksSourcesAndPreventsRelearning() throws {
        var cancelled: Set<UUID> = []
        var opened: [UUID] = []
        let (root, _, controller, _, _) = try fixture(cancelledMeetingIDs: { cancelled }, navigateToMeeting: {
            opened.append($0); return .opened
        })
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        let source = try #require(controller.selectedPage?.meetingIDs.first)
        #expect(controller.meetingSourceIssue(source) == nil)
        cancelled.insert(source)
        #expect(controller.title(forMeeting: source) == "Cancelled meeting")
        #expect(controller.meetingSourceIssue(source) == "This meeting was cancelled.")
        controller.openMeetingSource(source)
        controller.refreshFromMeetings(force: true)
        #expect(opened.isEmpty)
        #expect(!controller.availableMeetingIDs.contains(source))
        #expect(!controller.pages.flatMap(\.facts).flatMap(\.sources).contains(.meeting(source)))
    }

    @Test func validSourceFlushesDraftBeforeInjectedNavigationAndClosesGraph() throws {
        var opened: [UUID] = []
        var inspectedStore: WikiStore?
        var bodyAtDispatch: String?
        var inspectedPage: String?
        let (root, wiki, controller, origin, _) = try fixture(navigateToMeeting: { id in
            opened.append(id)
            bodyAtDispatch = inspectedStore?.loadPages().pages.first(where: { $0.id == inspectedPage })?.body
            return .opened
        })
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        inspectedStore = wiki
        inspectedPage = origin
        controller.openGraph()
        let source = try #require(controller.selectedPage?.meetingIDs.first)
        let draft = controller.draftBody + "\nSaved before source navigation."
        controller.setDraftBody(draft)
        controller.openMeetingSource(source)
        #expect(opened == [source])
        #expect(bodyAtDispatch == draft)
        #expect(controller.draftBody == draft)
        #expect(controller.selectedID == origin)
        #expect(!controller.graphOpen)
    }

    @Test func refusedSourceNavigationKeepsGraphAndReportsTheExactOutcome() throws {
        let refusals: [(WikiMeetingNavigationOutcome, String)] = [
            (.busy, "Finish the current recording and notes before opening a saved meeting. Your session is still running."),
            (.panelUnavailable, "The Meetings panel isn't available right now."),
            (.unavailable, "This source is no longer available in Meetings.")
        ]
        for (outcome, message) in refusals {
            var announcements: [String] = []
            let (root, _, controller, origin, _) = try fixture(navigateToMeeting: { _ in outcome },
                announce: { announcements.append($0) })
            defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
            controller.openGraph()
            let source = try #require(controller.selectedPage?.meetingIDs.first)
            controller.openMeetingSource(source)
            #expect(controller.graphOpen)
            #expect(controller.selectedID == origin)
            #expect(controller.notice == message)
            #expect(announcements.last == message)
        }
    }

    @Test func staleSourceStatesNeverReachTheInjectedNavigator() throws {
        for scenario in ["unrelated", "cancelled", "missing", "dismissed", "forgotten", "corrupt", "duplicate"] {
            var cancelled: Set<UUID> = []
            var opened: [UUID] = []
            let (root, wiki, controller, _, _) = try fixture(cancelledMeetingIDs: { cancelled }, navigateToMeeting: {
                opened.append($0); return .opened
            })
            defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
            controller.openGraph()
            let source = try #require(controller.selectedPage?.meetingIDs.first)
            let meetings = ScribeMeetingStore(directory: root.appendingPathComponent("meetings"))
            var requested = source
            switch scenario {
            case "unrelated": requested = UUID()
            case "cancelled": cancelled.insert(source)
            case "missing": try meetings.delete(id: source)
            case "dismissed":
                var record = try #require(meetings.loadAll().records.first(where: { $0.id == source }))
                record.dismissedAt = Date(timeIntervalSince1970: 2_000)
                try meetings.save(record)
            case "forgotten": try wiki.saveState(WikiStoreState(forgottenMeetings: [source]))
            case "corrupt": try "corrupt".write(to: wiki.stateURL, atomically: false, encoding: .utf8)
            case "duplicate":
                try FileManager.default.copyItem(at: meetings.directory.appendingPathComponent(ScribeMeetingRecord.fileName(for: source)),
                    to: meetings.directory.appendingPathComponent("duplicate.json"))
            default: Issue.record("Unknown fixture scenario: \(scenario)")
            }
            controller.openMeetingSource(requested)
            #expect(opened.isEmpty, "Rejected before navigation: \(scenario)")
            #expect(controller.graphOpen)
            #expect(controller.notice != nil)
        }
    }

    @Test func shutdownFlushesPendingEditsWithoutCreatingAWindow() throws {
        let (root, wiki, controller, origin, _) = try fixture()
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        let draft = controller.draftBody + "\nLast edit before the fixture closes."
        controller.setDraftBody(draft)
        #expect(controller.ownedWindow == nil)
        controller.shutdown()
        #expect(controller.ownedWindow == nil)
        #expect(wiki.loadPages().pages.first(where: { $0.id == origin })?.body == draft)
    }
}
