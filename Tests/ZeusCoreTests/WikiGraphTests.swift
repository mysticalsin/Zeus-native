import Foundation
import Testing
@testable import ZeusCore

@Suite("Memory focus graph")
struct WikiGraphTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private func page(_ id: String, sources: [WikiSource] = []) -> WikiPage {
        WikiPage(id: id, title: id.capitalized, sources: sources, updatedAt: now)
    }
    private func relation(_ id: String, title: String? = nil, sources: [WikiSource] = [], direction: WikiLinkDirection? = .outgoing) -> WikiRelatedPage {
        WikiRelatedPage(pageID: id, title: title ?? id.capitalized, sharedSources: sources, linkDirection: direction)
    }
    private func graph(_ focus: WikiPage, pages: [WikiPage], available: Set<UUID> = [], excluded: Set<UUID> = []) -> WikiGraphSnapshot {
        let relations = WikiRelationships.related(to: focus.id, in: pages, availableMeetingIDs: available, excluding: excluded)
        return .make(focus: focus, relationships: relations)
    }

    @Test func identicalRelationshipSetsHaveStableLayoutAndIDs() {
        let origin = page("origin")
        let relations = [relation("zulu"), relation("alpha"), relation("beta")]
        let first = WikiGraphSnapshot.make(focus: origin, relationships: relations)
        let reordered = WikiGraphSnapshot.make(focus: origin, relationships: relations.reversed())
        #expect(first == reordered)
        #expect(first.nodes.map(\.id) == ["origin", "alpha", "beta", "zulu"])
        #expect(first.nodes.first?.x == 0.5)
        #expect(first.nodes.first?.y == 0.5)
        #expect(first.edges.map(\.targetID) == ["alpha", "beta", "zulu"])
    }

    @Test func visualBoundsDoNotRemoveAccessibleOverflow() {
        let relations = (0..<40).map { relation(String(format: "node-%02d", $0)) }
        let snapshot = WikiGraphSnapshot.make(focus: page("origin"), relationships: relations, neighborLimit: 1_000)
        #expect(snapshot.nodes.count == 9)
        #expect(snapshot.edges.count == 8)
        #expect(snapshot.relationships.count == 40)
        #expect(snapshot.hiddenCount == 32)
        #expect(snapshot.totalRelationshipCount == 40)
        let zero = WikiGraphSnapshot.make(focus: page("origin"), relationships: relations, neighborLimit: -1)
        #expect(zero.nodes.count == 1)
        #expect(zero.edges.isEmpty)
        #expect(zero.hiddenCount == 40)
    }

    @Test func positionsRemainFiniteAndInsideTheCanvasForEverySupportedCount() {
        for count in 0...WikiGraphSnapshot.maximumNeighbors {
            let snapshot = WikiGraphSnapshot.make(focus: page("origin"), relationships: (0..<count).map { relation("node-\($0)") })
            #expect(snapshot.nodes.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0.1...0.9).contains($0.x) && (0.1...0.9).contains($0.y) })
            #expect(Set(snapshot.nodes.map(\.id)).count == count + 1)
            #expect(snapshot.edges.allSatisfy { $0.sourceID == "origin" && $0.targetID != "origin" })
        }
    }

    @Test func relationFiltersPreserveDualEvidenceAndDirections() {
        let source = WikiSource.meeting(UUID())
        let relations = [relation("linked", direction: .incoming), relation("shared", sources: [source], direction: nil),
                         relation("both", sources: [source], direction: .both)]
        let links = WikiGraphSnapshot.make(focus: page("origin"), relationships: relations, filter: .authoredLinks)
        #expect(Set(links.relationships.map(\.pageID)) == ["linked", "both"])
        #expect(links.edges.first(where: { $0.targetID == "both" })?.sharedSources == [source])
        #expect(links.edges.first(where: { $0.targetID == "both" })?.linkDirection == .both)
        let shared = WikiGraphSnapshot.make(focus: page("origin"), relationships: relations, filter: .sharedSources)
        #expect(Set(shared.relationships.map(\.pageID)) == ["shared", "both"])
        #expect(shared.edges.first(where: { $0.targetID == "shared" })?.linkDirection == nil)
    }

    @Test func searchFindsConnectedTitlesAndIDsWithoutCreatingNewEdges() {
        let relations = [relation("alpha-plan", title: "Launch Review"), relation("beta", title: "Weekly review")]
        let title = WikiGraphSnapshot.make(focus: page("origin"), relationships: relations, query: "  LAUNCH  review ")
        #expect(title.relationships.map(\.pageID) == ["alpha-plan"])
        let id = WikiGraphSnapshot.make(focus: page("origin"), relationships: relations, query: "alpha-plan")
        #expect(id.edges.map(\.targetID) == ["alpha-plan"])
        let none = WikiGraphSnapshot.make(focus: page("origin"), relationships: relations, query: "unrelated")
        #expect(none.edges.isEmpty)
        #expect(none.nodes.count == 1)
        #expect(none.totalRelationshipCount == 2)
    }

    @Test func authoredLinksProduceInspectableDirectionsThroughTheExistingPipeline() {
        var origin = page("origin"), target = page("target")
        origin.userEdited = true
        origin.body = "[[target]]"
        target.userEdited = true
        target.body = "[[origin]]"
        let snapshot = graph(origin, pages: [origin, target])
        #expect(snapshot.edges.count == 1)
        #expect(snapshot.edges.first?.linkDirection == .both)
        #expect(snapshot.edges.first?.sharedSources.isEmpty == true)
        #expect(snapshot.nodes.map(\.id) == ["origin", "target"])
    }

    @Test func missingCancelledAndForgottenMeetingEvidenceDisappears() {
        let live = UUID(), forgotten = UUID(), cancelled = UUID(), missing = UUID()
        let all = [live, forgotten, cancelled, missing].map(WikiSource.meeting)
        let origin = page("origin", sources: all), target = page("target", sources: all)
        let snapshot = graph(origin, pages: [origin, target], available: [live, forgotten, cancelled], excluded: [forgotten, cancelled])
        #expect(snapshot.edges.first?.sharedSources == [.meeting(live)])
        let removed = graph(origin, pages: [origin, target], available: [], excluded: [forgotten, cancelled])
        #expect(removed.edges.isEmpty)
        #expect(removed.nodes.map(\.id) == ["origin"])
    }

    @Test func forgettingAndDeletingRemoveGraphEdgesWithoutClearingReview() throws {
        let source = UUID(), remaining = UUID()
        var origin = page("origin", sources: [.meeting(source), .meeting(remaining)])
        origin.userEdited = true
        origin.body = "A reworded fact. [[target]]"
        origin.contributors = [source, remaining]
        let target = page("target", sources: [.meeting(source)])
        let removal = WikiCompiler.removeSourceReporting(.meeting(source), from: [origin, target], now: now)
        let retained = try #require(removal.pages.first(where: { $0.id == origin.id }))
        #expect(retained.needsReview)
        #expect(retained.exportedMarkdown() == nil)
        #expect(graph(retained, pages: removal.pages, available: [remaining], excluded: [source]).edges.isEmpty)
        #expect(graph(origin, pages: [origin], available: [source]).edges.isEmpty)
    }

    @Test func sourceKindsAndHistoricalContributorsDoNotInventConnections() {
        let id = UUID()
        let origin = page("origin", sources: [.meeting(id)])
        var historical = page("historical")
        historical.contributors = [id]
        let pages = [origin, page("memory", sources: [.memory(id)]), page("preference", sources: [.preference(id.uuidString)]), historical]
        #expect(graph(origin, pages: pages, available: [id]).edges.isEmpty)
    }

    @Test func duplicateConflictingAndEvidenceFreeRowsFailClosed() {
        let same = relation("same")
        let snapshot = WikiGraphSnapshot.make(focus: page("origin"), relationships: [same, same,
            relation("conflict", direction: .incoming), relation("conflict", direction: .outgoing),
            relation("empty", direction: nil), relation("origin"), relation("")])
        #expect(snapshot.relationships == [same])
        #expect(snapshot.edges.map(\.targetID) == ["same"])
    }

    @Test func noFocusedPageProducesNoOrphanNodes() {
        let snapshot = WikiGraphSnapshot.make(focus: nil, relationships: [relation("other")])
        #expect(snapshot.focusID == nil)
        #expect(snapshot.nodes.isEmpty)
        #expect(snapshot.edges.isEmpty)
        #expect(snapshot.relationships.isEmpty)
    }

    @Test func largeProjectionKeepsTheDrawingBoundedAndAllResultsReachable() {
        let relations = (0..<10_000).map { relation(String(format: "node-%05d", $0)) }
        let snapshot = WikiGraphSnapshot.make(focus: page("origin"), relationships: relations)
        #expect(snapshot.nodes.count == 9)
        #expect(snapshot.edges.count == 8)
        #expect(snapshot.relationships.count == 10_000)
        #expect(snapshot.hiddenCount == 9_992)
        #expect(snapshot.relationships.last?.pageID == "node-09999")
    }
}
