import Foundation
import Testing
@testable import ZeusCore

@Suite("Wiki relationships")
struct WikiRelationshipsTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func page(_ id: String, title: String = "Topic", sources: [WikiSource] = []) -> WikiPage {
        WikiPage(id: id, title: title, sources: sources, updatedAt: now)
    }

    @Test func sharedCurrentSourceIDsAreTheOnlyEvidence() {
        let meeting = UUID(), other = UUID()
        var historical = page("history", sources: [.meeting(other)])
        historical.contributors = [meeting]
        historical.body = "Same title, words and former source are not a connection."
        let pages = [page("origin", sources: [.meeting(meeting)]),
                     page("shared", title: "Different title", sources: [.meeting(meeting)]),
                     page("same-title"), historical]
        let related = WikiRelationships.related(to: "origin", in: pages, availableMeetingIDs: [meeting, other])
        #expect(related.map(\.pageID) == ["shared"])
        #expect(related.first?.sharedSources == [.meeting(meeting)])
    }

    @Test func duplicateSourcesAndPagesDoNotInflateConnections() {
        let meeting = UUID(), memory = UUID()
        let origin = page("origin", sources: [.meeting(meeting), .meeting(meeting), .memory(memory), .preference("tone")])
        let other = page("other", sources: [.preference("tone"), .memory(memory), .meeting(meeting), .meeting(meeting)])
        let result = WikiRelationships.related(to: origin.id, in: [origin, other, other, origin], availableMeetingIDs: [meeting])
        #expect(result.count == 1)
        #expect(result.first?.sharedSources.count == 3)
        #expect(Set(result.first?.sharedSources ?? []) == Set(origin.sources))
    }

    @Test func missingAndForgottenEvidenceNeverResurrectsEditedSources() {
        let live = UUID(), missing = UUID(), forgotten = UUID(), removedOrigin = UUID(), removedTarget = UUID()
        let all: [WikiSource] = [live, missing, forgotten, removedOrigin, removedTarget].map(WikiSource.meeting)
        var origin = page("origin", sources: all)
        var target = page("target", sources: all)
        origin.userEdited = true
        origin.needsReview = true
        origin.forgottenContributors = [removedOrigin]
        target.forgottenContributors = [removedTarget]
        let pages = [origin, target]
        let result = WikiRelationships.related(to: origin.id, in: pages,
            availableMeetingIDs: [live, forgotten, removedOrigin, removedTarget], excluding: [forgotten])
        #expect(result.first?.sharedSources == [.meeting(live)])
        #expect(pages[0] == origin)
        #expect(pages[1] == target)
        #expect(pages[0].exportedMarkdown() == nil)
    }

    @Test func forgettingRemovesEdgesAndPreservesReviewRequirements() {
        let meeting = UUID(), remaining = UUID()
        var origin = page("origin", sources: [.meeting(meeting), .meeting(remaining)])
        origin.userEdited = true
        origin.body = "A manually reworded fact."
        origin.contributors = [meeting, remaining]
        let target = page("target", sources: [.meeting(meeting)])
        #expect(WikiRelationships.related(to: origin.id, in: [origin, target], availableMeetingIDs: [meeting]).count == 1)
        let removed = WikiCompiler.removeSourceReporting(.meeting(meeting), from: [origin, target], now: now)
        #expect(WikiRelationships.related(to: origin.id, in: removed.pages, availableMeetingIDs: [meeting], excluding: [meeting]).isEmpty)
        #expect(removed.pages.first(where: { $0.id == origin.id })?.needsReview == true)
    }

    @Test func relationshipsHaveStableEvidenceAndPageOrdering() {
        let one = UUID(), two = UUID()
        let pages = [page("origin", sources: [.meeting(one), .meeting(two)]),
                     page("z", title: "Zulu", sources: [.meeting(two), .meeting(one)]),
                     page("b", title: "Alpha", sources: [.meeting(one)]),
                     page("a", title: "Alpha", sources: [.meeting(one)])]
        let first = WikiRelationships.related(to: "origin", in: pages, availableMeetingIDs: [one, two])
        let reversed = WikiRelationships.related(to: "origin", in: pages.reversed(), availableMeetingIDs: [one, two])
        #expect(first == reversed)
        #expect(first.map(\.pageID) == ["z", "a", "b"])
    }

    @Test func aSourceOfAnotherKindIsNotTheSameEvidence() {
        let id = UUID()
        let pages = [page("origin", sources: [.meeting(id)]),
                     page("memory", sources: [.memory(id)]),
                     page("preference", sources: [.preference(id.uuidString)])]
        #expect(WikiRelationships.related(to: "origin", in: pages, availableMeetingIDs: [id]).isEmpty)
        #expect(WikiRelationships.related(to: "deleted-page", in: pages, availableMeetingIDs: [id]).isEmpty)
    }

    @Test func compiledPagesBecomeConnectedByAnExplicitEditedLink() throws {
        let first = ScribeMeetingRecord(id: UUID(), title: "Project Alpha", endedAt: now, duration: 60,
            notes: ScribeMeetingNotes(decisions: ["A synthetic decision"]), transcript: [])
        let second = ScribeMeetingRecord(id: UUID(), title: "Project Beta", endedAt: now, duration: 60,
            notes: ScribeMeetingNotes(decisions: ["Another synthetic decision"]), transcript: [])
        var pages = WikiCompiler.reconcile(meetings: [first, second], into: [], now: now).pages
        let alpha = try #require(pages.firstIndex(where: { $0.meetingIDs.contains(first.id) }))
        let beta = try #require(pages.firstIndex(where: { $0.meetingIDs.contains(second.id) }))
        let saved: Set<UUID> = [first.id, second.id]
        #expect(pages.count == 2)
        #expect(WikiRelationships.related(to: pages[alpha].id, in: pages, availableMeetingIDs: saved).isEmpty)
        pages[alpha].userEdited = true
        pages[alpha].body += "\nSee [[  project   BETA  ]]."
        let outgoing = WikiRelationships.related(to: pages[alpha].id, in: pages, availableMeetingIDs: saved)
        #expect(outgoing.first?.pageID == pages[beta].id)
        #expect(outgoing.first?.linkDirection == .outgoing)
        #expect(outgoing.first?.sharedSources.isEmpty == true)
        let incoming = WikiRelationships.related(to: pages[beta].id, in: pages, availableMeetingIDs: saved)
        #expect(incoming.first?.pageID == pages[alpha].id)
        #expect(incoming.first?.linkDirection == .incoming)
    }

    @Test func exactIDsDisambiguateTitlesAndReciprocalLinksKeepTheirDirection() {
        var origin = page("origin", title: "Start")
        var target = page("target", title: "Ambiguous")
        let twin = page("twin", title: "ambiguous")
        origin.userEdited = true
        target.userEdited = true
        origin.body = "[[target]] [[target]]"
        target.body = "[[Start]]"
        let related = WikiRelationships.related(to: origin.id, in: [origin, target, twin], availableMeetingIDs: [])
        #expect(related.count == 1)
        #expect(related.first?.linkDirection == .both)
        #expect(related.first?.pageID == target.id)
    }

    @Test func ambiguousMissingSelfAndUnsupportedLinksAreNotConnections() {
        var origin = page("origin", title: "Start")
        origin.userEdited = true
        origin.body = "[[ambiguous]] [[Missing]] [[Start]] [[origin]] [[Target|Alias]] [[Target#Section]] [[Target\n]]"
        let others = [page("one", title: "Ambiguous"), page("two", title: " AMBIGUOUS "), page("target", title: "Target")]
        #expect(WikiRelationships.related(to: origin.id, in: [origin] + others, availableMeetingIDs: []).isEmpty)
        origin.body = "[[target]]"
        #expect(WikiRelationships.related(to: origin.id, in: [origin], availableMeetingIDs: []).isEmpty)
    }

    @Test func generatedMeetingTextAndUnreviewedForgottenTextCannotCreateLinks() {
        var origin = page("origin", title: "Start")
        let target = page("target", title: "Target")
        origin.body = "A transcribed [[Target]] is not an authored connection."
        #expect(WikiRelationships.related(to: origin.id, in: [origin, target], availableMeetingIDs: []).isEmpty)
        origin.userEdited = true
        origin.needsReview = true
        #expect(WikiRelationships.related(to: origin.id, in: [origin, target], availableMeetingIDs: []).isEmpty)
        origin.needsReview = false
        origin.forgottenContributors = [UUID()]
        #expect(WikiRelationships.related(to: origin.id, in: [origin, target], availableMeetingIDs: []).isEmpty)
    }

    @Test func deletingAnExplicitTargetRemovesBothDirectionsWithoutChangingTheDraft() {
        var origin = page("origin", title: "Start")
        var target = page("target", title: "Target")
        origin.userEdited = true
        origin.body = "[[Target]]"
        target.userEdited = true
        target.body = "[[Start]]"
        #expect(WikiRelationships.related(to: origin.id, in: [origin, target], availableMeetingIDs: []).first?.linkDirection == .both)
        #expect(WikiRelationships.related(to: origin.id, in: [origin], availableMeetingIDs: []).isEmpty)
        #expect(origin.body == "[[Target]]")
    }
}
