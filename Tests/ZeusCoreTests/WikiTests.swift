import Foundation
import Testing
@testable import ZeusCore

@Suite struct WikiTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_100_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_200_000)

    // MARK: Helpers (synthetic data only)

    private func meeting(
        _ title: String,
        id: UUID = UUID(),
        day: Int = 0,
        decisions: [String] = [],
        actions: [(String, Bool)] = [],
        privateNotes: String = "",
        summary: String = "",
        participants: [String] = []
    ) -> ScribeMeetingRecord {
        let session = ScribeSessionID(rawValue: id)
        let transcript = participants.enumerated().map { index, name in
            ScribeTranscriptSegment(
                id: "s\(index)", session: session, speaker: .participant(name),
                start: Double(index), end: Double(index) + 1, text: "Synthetic line \(index)", isFinal: true
            )
        }
        return ScribeMeetingRecord(
            id: id,
            title: title,
            endedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(day) * 86_400),
            duration: 600,
            notes: ScribeMeetingNotes(
                summary: summary,
                decisions: decisions,
                actionItems: actions.map { ScribeActionItem(text: $0.0, done: $0.1) },
                privateNotes: privateNotes
            ),
            transcript: transcript
        )
    }

    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiki-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        guard let resolved = realpath(base.path, nil) else {
            throw WikiStoreError.write("realpath failed for \(base.path)")
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1) & 0o777
    }

    private func kinds(_ text: String, names: [String] = []) -> Set<SensitiveFinding.Kind> {
        Set(SensitiveInfoScanner.scan(text, participantNames: names).map(\.kind))
    }

    private func samplePage(id: String = "topic-sample", body: String = "Plain body.") -> WikiPage {
        WikiPage(id: id, title: "Sample", body: body, updatedAt: t0)
    }

    // MARK: Topics

    @Test func topicIDIgnoresDatesCaseAndAccents() {
        #expect(WikiCompiler.topicID(forTitle: "Weekly sync 11/07") == "topic-weekly-sync")
        #expect(WikiCompiler.topicID(forTitle: "  WEEKLY   Sync 2026-11-14 ") == "topic-weekly-sync")
        #expect(WikiCompiler.topicID(forTitle: "Réunion équipe") == "topic-reunion-equipe")
        #expect(WikiCompiler.topicID(forTitle: "2026-11-07") == "topic-meetings")
        let other = WikiCompiler.topicID(forTitle: "週次会議")
        #expect(other.hasPrefix("topic-t-"))
        #expect(WikiStore.isValidID(other))
        #expect(other != WikiCompiler.topicID(forTitle: "月次会議"))
    }

    // MARK: Compiler

    @Test func compilerBuildsTopicPageFromDecisionsAndActions() {
        let m = meeting(
            "Roadmap review",
            decisions: ["We decided to ship the beta on Friday."],
            actions: [("Priya will draft the notes.", false), ("Omar will book the room.", true)]
        )
        let pages = WikiCompiler.compile(meetings: [m], into: [], now: t0)
        #expect(pages.count == 1)
        let page = pages[0]
        #expect(page.id == "topic-roadmap-review")
        #expect(page.title == "Roadmap review")
        #expect(page.scope == .personal)
        #expect(!page.pinned)
        #expect(page.promotedBy == nil && page.promotedAt == nil)
        #expect(page.sources == [.meeting(m.id)])
        #expect(page.body.contains("## Decisions"))
        #expect(page.body.contains("- We decided to ship the beta on Friday."))
        #expect(page.body.contains("## Action items"))
        #expect(page.body.contains("- [ ] Priya will draft the notes."))
        #expect(page.body.contains("- [x] Omar will book the room."))
    }

    @Test func compilerSkipsMeetingsWithNothingToLearn() {
        let m = meeting("Chat", decisions: ["   "], actions: [])
        #expect(WikiCompiler.compile(meetings: [m], into: [], now: t0).isEmpty)
    }

    @Test func compilerMergesSameTopicAndDedupesFacts() {
        let first = meeting("Weekly sync 11/07", day: 0, decisions: ["Keep the weekly cadence.", "Use the shared board."])
        let second = meeting("Weekly sync 11/14", day: 7, decisions: ["keep the weekly cadence", "Move standup to 10."])
        let pages = WikiCompiler.compile(meetings: [second, first], into: [], now: t0)
        #expect(pages.count == 1)
        let page = pages[0]
        #expect(page.facts.count == 3)
        let shared = page.facts.first { WikiCompiler.normalizedKey($0.text) == "keep the weekly cadence" }
        #expect(shared?.sources.count == 2)
        #expect(Set(page.sources) == [.meeting(first.id), .meeting(second.id)])
        #expect(page.body.components(separatedBy: "Keep the weekly cadence.").count == 2)
        #expect(!page.body.contains("- keep the weekly cadence"))
    }

    @Test func compilerIsIdempotent() {
        let m = meeting("Planning", decisions: ["We agreed on two sprints."], actions: [("Lee will update the plan.", false)])
        let first = WikiCompiler.compile(meetings: [m], into: [], now: t0)
        let second = WikiCompiler.compile(meetings: [m], into: first, now: t1)
        #expect(second == first)
    }

    @Test func compilerUpdatesWhenMeetingContentChanges() {
        let id = UUID()
        let before = meeting("Planning", id: id, decisions: ["Old decision text."])
        let first = WikiCompiler.compile(meetings: [before], into: [], now: t0)
        let after = meeting("Planning", id: id, decisions: ["New decision text."])
        let second = WikiCompiler.compile(meetings: [after], into: first, now: t1)
        #expect(second.count == 1)
        #expect(!second[0].body.contains("Old decision text."))
        #expect(second[0].body.contains("New decision text."))
        #expect(second[0].updatedAt == t1)
    }

    @Test func recompileKeepsPinAndGlobalScopeWhenNothingNewWasLearned() throws {
        let a = meeting("Planning", day: 0, decisions: ["Ship the beta."])
        var pages = WikiCompiler.compile(meetings: [a], into: [], now: t0)
        pages[0].pinned = true
        pages[0] = try WikiPromotion.promote(pages[0], promotedBy: "tester", acknowledged: [], now: t0)
        let same = WikiCompiler.compile(meetings: [a], into: pages, now: t1)
        #expect(same == pages)
        #expect(same[0].scope == .global && same[0].promotedBy == "tester")
    }

    @Test func learningNewFactsMakesAGlobalPagePersonalAgain() throws {
        let a = meeting("Planning", day: 0, decisions: ["Ship the beta."])
        var pages = WikiCompiler.compile(meetings: [a], into: [], now: t0)
        pages[0].pinned = true
        pages[0] = try WikiPromotion.promote(pages[0], promotedBy: "tester", acknowledged: [], now: t0)
        let b = meeting("Planning", day: 1, decisions: ["Email dana@example.com the plan."])
        let next = WikiCompiler.compile(meetings: [a, b], into: pages, now: t1)
        #expect(next.count == 1)
        #expect(next[0].pinned)
        #expect(next[0].scope == .personal)
        #expect(next[0].promotedBy == nil && next[0].promotedAt == nil)
        #expect(next[0].facts.count == 2)
    }

    @Test func removingASourceKeepsAGlobalPageGlobal() throws {
        let a = meeting("Planning", day: 0, decisions: ["Ship the beta."])
        let b = meeting("Planning", day: 1, decisions: ["Hire one more engineer."])
        var pages = WikiCompiler.compile(meetings: [a, b], into: [], now: t0)
        pages[0] = try WikiPromotion.promote(pages[0], promotedBy: "tester", acknowledged: [], now: t0)
        let after = WikiCompiler.removeSource(.meeting(b.id), from: pages, now: t1)
        #expect(after.count == 1)
        #expect(after[0].scope == .global)
        #expect(!after[0].body.contains("Hire one more engineer."))
    }

    @Test func privateNotesSummaryAndTranscriptAreNeverIngested() throws {
        let m = meeting(
            "Budget talk",
            decisions: ["We decided to freeze hiring."],
            actions: [("Sam will send the numbers.", false)],
            privateNotes: "PRIVATE-NOTE-CANARY-7741 remind me to call the clinic",
            summary: "SUMMARY-CANARY-5521",
            participants: ["Dana Whitfield"]
        )
        let pages = WikiCompiler.compile(meetings: [m], into: [], now: t0)
        let encoder = JSONEncoder()
        let json = String(decoding: try encoder.encode(pages), as: UTF8.self)
        #expect(!json.contains("PRIVATE-NOTE-CANARY-7741"))
        #expect(!json.contains("SUMMARY-CANARY-5521"))
        #expect(!json.contains("Synthetic line"))
        #expect(pages[0].participantNames == ["Dana Whitfield"])
    }

    @Test func removingASourceRemovesItsFactsAndDropsEmptyPages() {
        let a = meeting("Weekly sync 1", day: 0, decisions: ["Shared decision.", "Only in A."])
        let b = meeting("Weekly sync 2", day: 1, decisions: ["Shared decision.", "Only in B."])
        let other = meeting("Hiring loop", day: 2, decisions: ["Unrelated decision."])
        let pages = WikiCompiler.compile(meetings: [a, b, other], into: [], now: t0)
        #expect(pages.count == 2)

        let afterA = WikiCompiler.removeSource(.meeting(a.id), from: pages, now: t1)
        let sync = afterA.first { $0.id == "topic-weekly-sync" }
        #expect(sync != nil)
        #expect(sync?.body.contains("Only in A.") == false)
        #expect(sync?.body.contains("Only in B.") == true)
        #expect(sync?.body.contains("Shared decision.") == true)
        #expect(sync?.sources == [.meeting(b.id)])
        #expect(sync?.facts.first { $0.text == "Shared decision." }?.sources == [.meeting(b.id)])
        #expect(afterA.first { $0.id == "topic-hiring-loop" } == pages.first { $0.id == "topic-hiring-loop" })

        let afterB = WikiCompiler.removeSource(.meeting(b.id), from: afterA, now: t1)
        #expect(afterB.map(\.id) == ["topic-hiring-loop"])
    }

    @Test func removingAMeetingThatIsNotThereChangesNothing() {
        let a = meeting("Planning", decisions: ["Ship it."])
        let pages = WikiCompiler.compile(meetings: [a], into: [], now: t0)
        #expect(WikiCompiler.removeSource(.meeting(UUID()), from: pages, now: t1) == pages)
    }

    @Test func compileDropsFactsOfMeetingsThatNoLongerExist() {
        let a = meeting("Weekly sync 1", day: 0, decisions: ["Only in A."])
        let b = meeting("Weekly sync 2", day: 1, decisions: ["Only in B."])
        let pages = WikiCompiler.compile(meetings: [a, b], into: [], now: t0)

        let removed = WikiCompiler.compile(meetings: [b], into: pages, now: t1)
        #expect(removed.count == 1)
        #expect(!removed[0].body.contains("Only in A."))
        #expect(removed[0].body.contains("Only in B."))

        // Some file could not be read: an unreadable meeting is not a deleted one.
        let kept = WikiCompiler.compile(meetings: [b], into: pages, removeMissing: false, now: t1)
        #expect(kept[0].body.contains("Only in A."))

        let none = WikiCompiler.compile(meetings: [], into: pages, now: t1)
        #expect(none.isEmpty)
    }

    @Test func forgottenMeetingsAreNeverIngested() {
        let a = meeting("Planning", decisions: ["Ship it."])
        #expect(WikiCompiler.compile(meetings: [a], into: [], excluding: [a.id], now: t0).isEmpty)

        let pages = WikiCompiler.compile(meetings: [a], into: [], now: t0)
        #expect(WikiCompiler.compile(meetings: [a], into: pages, excluding: [a.id], now: t1).isEmpty)
    }

    @Test func editedBodyIsKeptAndOnlyForgottenLinesAreRemoved() {
        let a = meeting("Planning", day: 0, decisions: ["Decision from A."])
        let b = meeting("Planning", day: 1, decisions: ["Decision from B."])
        var pages = WikiCompiler.compile(meetings: [a, b], into: [], now: t0)
        pages[0].applyEdit(body: pages[0].body + "\nMy own remark.", now: t0)
        #expect(pages[0].userEdited)

        let recompiled = WikiCompiler.compile(meetings: [a, b], into: pages, now: t1)
        #expect(recompiled[0].body.contains("My own remark."))

        let forgot = WikiCompiler.removeSource(.meeting(a.id), from: recompiled, now: t1)
        #expect(forgot[0].body.contains("My own remark."))
        #expect(!forgot[0].body.contains("Decision from A."))
        #expect(forgot[0].body.contains("Decision from B."))
    }

    @Test func editedSourcedLineIsRemovedWhenItsMeetingIsForgotten() {
        let a = meeting("Planning", day: 0, decisions: ["Decision from A."])
        let b = meeting("Planning", day: 1, decisions: ["Decision from B."])
        var pages = WikiCompiler.compile(meetings: [a, b], into: [], now: t0)
        let edited = pages[0].body.replacingOccurrences(of: "Decision from A.", with: "Decision from A. (confirmed)")
        pages[0].applyEdit(body: edited + "\nMy own remark.", now: t0)
        #expect(pages[0].body.contains("(confirmed)"))

        let forgot = WikiCompiler.removeSourceReporting(.meeting(a.id), from: pages, now: t1)
        let body = forgot.pages[0].body
        #expect(!body.contains("Decision from A."))
        #expect(!body.contains("(confirmed)"))
        #expect(body.contains("Decision from B."))
        #expect(body.contains("My own remark."))
        #expect(forgot.editedLinesRemoved == 1)
        #expect(!forgot.pages[0].markdown().contains("Decision from A."))

        // Fully reworded, but the invisible marker still ties the line to its fact.
        var reworded = pages
        let lines = reworded[0].body.components(separatedBy: "\n").map { line -> String in
            guard line.contains("Decision from A.") else { return line }
            var marker = String.UnicodeScalarView()
            marker.append(contentsOf: line.unicodeScalars.suffix(34))
            return "Totally different words" + String(marker)
        }
        reworded[0].applyEdit(body: lines.joined(separator: "\n"), now: t0)
        let after = WikiCompiler.removeSource(.meeting(a.id), from: reworded, now: t1)
        #expect(!after[0].body.contains("Totally different words"))
        #expect(after[0].body.contains("Decision from B."))
    }

    @Test func editedLineOfAKeptFactSurvivesForgettingAnotherMeeting() {
        let a = meeting("Planning", day: 0, decisions: ["Shared decision.", "Only A."])
        let b = meeting("Planning", day: 1, decisions: ["Shared decision."])
        var pages = WikiCompiler.compile(meetings: [a, b], into: [], now: t0)
        pages[0].applyEdit(body: pages[0].body.replacingOccurrences(of: "Shared decision.", with: "Shared decision. (confirmed)"), now: t0)
        let after = WikiCompiler.removeSourceReporting(.meeting(a.id), from: pages, now: t1)
        #expect(after.pages[0].body.contains("Shared decision. (confirmed)"))
        #expect(!after.pages[0].body.contains("Only A."))
        #expect(after.editedLinesRemoved == 0)
        // A contributed to an edited page, so the person still has to look at it.
        #expect(after.pages[0].needsReview)
    }

    @Test func markersAreInvisibleInExport() {
        let a = meeting("Planning", decisions: ["Ship it."])
        let page = WikiCompiler.compile(meetings: [a], into: [], now: t0)[0]
        #expect(page.markdown() == "# Planning\n\n## Decisions\n- Ship it.\n")
    }

    @Test func joinedLineWithForgottenAndKeptMarkersIsRemovedEntirely() throws {
        let a = meeting("Planning", day: 0, decisions: ["Decision from A."])
        let b = meeting("Planning", day: 1, decisions: ["Decision from B."])
        var pages = WikiCompiler.compile(meetings: [a, b], into: [], now: t0)
        let lines = pages[0].body.components(separatedBy: "\n")
        let lineA = try #require(lines.first { $0.contains("Decision from A.") })
        let lineB = try #require(lines.first { $0.contains("Decision from B.") })
        pages[0].applyEdit(body: "## Decisions\n" + lineA + " " + lineB + "\nMy own remark.", now: t0)

        let forgot = WikiCompiler.removeSourceReporting(.meeting(a.id), from: pages, now: t1)
        let body = forgot.pages[0].body
        #expect(!body.contains("Decision from A."))
        #expect(!body.contains("Decision from B."))
        #expect(body.contains("My own remark."))
        #expect(forgot.editedLinesRemoved == 1)
        #expect(forgot.pages[0].needsReview)
        #expect(forgot.pages[0].exportedMarkdown() == nil)
        #expect(!forgot.pages[0].markdown().contains("Decision from A."))
    }

    @Test func markerEditedAwayFlagsThePageAndBlocksExportAndPromotion() throws {
        let a = meeting("Planning", day: 0, decisions: ["Decision from A."])
        let b = meeting("Planning", day: 1, decisions: ["Decision from B."])
        var pages = WikiCompiler.compile(meetings: [a, b], into: [], now: t0)
        #expect(pages[0].contributors.count == 2)
        let reworded = pages[0].body.components(separatedBy: "\n").map { line in
            line.contains("Decision from A.") ? "Reworded decision" : line
        }
        pages[0].applyEdit(body: reworded.joined(separator: "\n"), now: t0)

        let after = WikiCompiler.removeSource(.meeting(a.id), from: pages, meetingTitle: "Planning", now: t1)
        let page = after[0]
        #expect(page.needsReview)
        #expect(page.reviewReason?.contains("“Planning”") == true)
        // The forgotten id stays a contributor until the review is cleared.
        #expect(page.contributors.contains(a.id))
        #expect(page.forgottenContributors == [a.id])
        #expect(page.exportedMarkdown() == nil)
        #expect(throws: WikiPromotionError.needsReview) {
            _ = try WikiPromotion.promote(page, promotedBy: "tester", acknowledged: [], now: t1)
        }

        // The same holds when the meeting was forgotten through a compile.
        let viaCompile = WikiCompiler.compile(meetings: [a, b], into: pages, excluding: [a.id], now: t1)
        #expect(viaCompile[0].needsReview)

        var cleared = page
        cleared.clearReview(now: t1)
        #expect(!cleared.needsReview && cleared.reviewReason == nil)
        #expect(!cleared.contributors.contains(a.id) && cleared.forgottenContributors.isEmpty)
        #expect(cleared.contributors == [b.id])
        #expect(cleared.userEdited)
        #expect(cleared.exportedMarkdown() != nil)
        _ = try WikiPromotion.promote(cleared, promotedBy: "tester", acknowledged: [], now: t1)
    }

    @Test func rewordedLineWithMarkerRemovedAndFactGoneLaterStillFlagsOnForget() {
        let id = UUID()
        let a = meeting("Planning", id: id, day: 0, decisions: ["Decision from A."])
        let b = meeting("Planning", day: 1, decisions: ["Decision from B."])
        var pages = WikiCompiler.compile(meetings: [a, b], into: [], now: t0)
        let reworded = pages[0].body.components(separatedBy: "\n").map { line in
            line.contains("Decision from A.") ? "Our own wording of it" : line
        }
        pages[0].applyEdit(body: reworded.joined(separator: "\n"), now: t0)
        #expect(pages[0].userEdited)

        // A's saved meeting later loses that decision in ordinary reconciliation: no fact of A is left.
        let aEmptied = meeting("Planning", id: id, day: 0, decisions: [])
        let later = WikiCompiler.compile(meetings: [aEmptied, b], into: pages, now: t1)
        #expect(!later[0].needsReview)
        #expect(!later[0].facts.contains { $0.sources.contains(.meeting(id)) })
        #expect(later[0].contributors.contains(id))

        // Forgetting A now finds neither marker nor fact, and still flags the page.
        let forgot = WikiCompiler.removeSource(.meeting(id), from: later, meetingTitle: "Planning", now: t1)
        #expect(forgot[0].needsReview)
        #expect(forgot[0].exportedMarkdown() == nil)
        #expect(forgot[0].body.contains("Our own wording of it"))
        let viaCompile = WikiCompiler.compile(meetings: [aEmptied, b], into: later, excluding: [id], now: t1)
        #expect(viaCompile[0].needsReview)
    }

    @Test func mergedFactSharedByTwoMeetingsStillFlagsAnEditedPageWhenOneIsForgotten() throws {
        let a = meeting("Planning", day: 0, decisions: ["Shared decision."])
        let b = meeting("Planning", day: 1, decisions: ["Shared decision."])
        var pages = WikiCompiler.compile(meetings: [a, b], into: [], now: t0)
        #expect(pages[0].facts.count == 1 && pages[0].facts[0].sources.count == 2)
        pages[0].applyEdit(body: pages[0].body + "\nAdded from the A discussion: keep the budget flat.", now: t0)

        let after = WikiCompiler.removeSource(.meeting(a.id), from: pages, now: t1)
        #expect(after[0].facts.first?.sources == [.meeting(b.id)])
        #expect(after[0].needsReview)
        #expect(after[0].exportedMarkdown() == nil)
        #expect(throws: WikiPromotionError.needsReview) {
            _ = try WikiPromotion.promote(after[0], promotedBy: "tester", acknowledged: [], now: t1)
        }
    }

    @Test func uneditedPageIsRegeneratedWithoutAForgottenMeetingsFacts() {
        let a = meeting("Planning", day: 0, decisions: ["Shared decision.", "Only in A."], actions: [("Ana will book it.", false)])
        let b = meeting("Planning", day: 1, decisions: ["Shared decision.", "Only in B."])
        let pages = WikiCompiler.compile(meetings: [a, b], into: [], now: t0)
        #expect(!pages[0].userEdited)

        let removed = WikiCompiler.removeSource(.meeting(a.id), from: pages, now: t1)
        #expect(!removed[0].needsReview && !removed[0].userEdited)
        #expect(removed[0].contributors == [b.id])
        #expect(removed[0].body == WikiCompiler.render(facts: removed[0].facts))
        #expect(!removed[0].body.contains("Only in A."))
        #expect(!removed[0].body.contains("Ana will book it."))
        #expect(removed[0].body.contains("Shared decision."))
        #expect(removed[0].body.contains("Only in B."))

        let viaCompile = WikiCompiler.compile(meetings: [a, b], into: pages, excluding: [a.id], now: t1)
        #expect(viaCompile[0].body == removed[0].body)
        #expect(viaCompile[0].facts == removed[0].facts)
        #expect(viaCompile[0].contributors == [b.id] && !viaCompile[0].needsReview)
    }

    @Test func uneditedPageBodyIsRegeneratedEvenWhenTheStoredBodyDrifted() {
        let a = meeting("Planning", day: 0, decisions: ["Only in A."])
        let b = meeting("Planning", day: 1, decisions: ["Only in B."])
        var pages = WikiCompiler.compile(meetings: [a, b], into: [], now: t0)
        // Not through applyEdit, so the page is still unedited: a stale body can't keep forgotten text alive.
        pages[0].body += "\nOnly in A. (stale copy)"
        let removed = WikiCompiler.removeSource(.meeting(a.id), from: pages, now: t1)
        #expect(!removed[0].body.contains("Only in A."))
    }

    @Test func userEditedIsNeverClearedAutomatically() {
        let a = meeting("Planning", day: 0, decisions: ["Decision from A."])
        let b = meeting("Planning", day: 1, decisions: ["Decision from B."])
        var pages = WikiCompiler.compile(meetings: [a, b], into: [], now: t0)
        pages[0].applyEdit(body: "My text", now: t0)
        var next = WikiCompiler.compile(meetings: [a, b], into: pages, now: t1)
        next = WikiCompiler.removeSource(.meeting(a.id), from: next, now: t1)
        next[0].clearReview(now: t1)
        #expect(next[0].userEdited)
        #expect(next[0].body == "My text")
    }

    @Test func pageFilesWithTheOldBodyEditedKeyStillLoad() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        var page = samplePage()
        page.applyEdit(body: "Edited.", now: t1)
        try store.save(page)
        let file = dir.appendingPathComponent("topic-sample.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        object["bodyEdited"] = object["userEdited"]
        object["userEdited"] = nil
        object["forgottenContributors"] = nil
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        let loaded = store.loadPages()
        #expect(loaded.failures.isEmpty)
        #expect(loaded.pages.first?.userEdited == true)
        #expect(loaded.pages.first?.forgottenContributors == [])
    }

    @Test func reviewFlagSurvivesRecompileAndStoreRoundTrip() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = meeting("Planning", day: 0, decisions: ["Decision from A."])
        let b = meeting("Planning", day: 1, decisions: ["Decision from B."])
        var pages = WikiCompiler.compile(meetings: [a, b], into: [], now: t0)
        pages[0].applyEdit(body: "Reworded decision", now: t0)
        let flagged = WikiCompiler.removeSource(.meeting(a.id), from: pages, now: t1)
        let again = WikiCompiler.compile(meetings: [b], into: flagged, now: t1)
        #expect(again[0].needsReview)

        let store = WikiStore(root: dir)
        try store.save(again[0])
        #expect(store.loadPages().pages.first?.needsReview == true)
        // A page file written before the review fields existed still loads.
        let file = dir.appendingPathComponent("\(again[0].id).json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        object["needsReview"] = nil
        object["reviewReason"] = nil
        object["contributors"] = nil
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        let legacy = store.loadPages()
        #expect(legacy.failures.isEmpty)
        #expect(legacy.pages.first?.needsReview == false)
    }

    @Test func failedSaveIsRetainedThroughPauseAndRetriedOnRefresh() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appendingPathComponent("wiki")
        // A file where the folder belongs makes every write fail.
        try Data("blocked".utf8).write(to: root)
        let store = WikiStore(root: root)
        let a = meeting("Planning", decisions: ["Ship it."])
        var pending = WikiPendingWrites()
        var effective: [WikiPage] = []

        // Ingestion creates a page, and saving it fails.
        effective = pending.stage(replacing: effective, with: WikiCompiler.compile(meetings: [a], into: effective, now: t0))
        #expect(pending.retry(using: store).count == 1)
        let page = try #require(effective.first)
        #expect(pending.intent(for: page.id) == .save(page))

        // Learning is paused, then a refresh compiles without ingesting: the intent stays and is tried again.
        let paused = WikiCompiler.compile(meetings: [a], into: effective, ingest: false, now: t1)
        effective = pending.stage(replacing: effective, with: paused)
        #expect(effective == [page])
        #expect(pending.intent(for: page.id) == .save(page))
        #expect(pending.retry(using: store).count == 1)
        #expect(pending.intent(for: page.id) == .save(page))

        // Once the disk works, the same page value is committed and the intent is cleared.
        try FileManager.default.removeItem(at: root)
        #expect(pending.retry(using: store).isEmpty)
        #expect(pending.isEmpty)
        #expect(store.loadPages().pages == [page])
    }

    @Test func failedEditSaveIsRetainedAndRetriedAfterASelectionChange() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appendingPathComponent("wiki")
        let store = WikiStore(root: root)
        let other = samplePage(id: "topic-other", body: "Other page.")
        var page = samplePage(body: "Original.")
        try store.save(page)
        try store.save(other)
        // Every write now fails.
        try FileManager.default.removeItem(at: root)
        try Data("blocked".utf8).write(to: root)

        var pending = WikiPendingWrites()
        var effective = [page, other]
        page.applyEdit(body: "Typed text the disk never got.", now: t1)
        effective[0] = page
        let failure = pending.commit(page, using: store)
        #expect(failure != nil)
        #expect(pending.intent(for: page.id) == .save(page))

        // Selection changes (and a refresh compiles nothing new): the edit is still the effective value.
        #expect(!pending.retry(using: store).isEmpty)
        let compiled = pending.stage(replacing: effective, with: WikiCompiler.compile(meetings: [], into: effective, now: t1))
        #expect(compiled == effective)
        #expect(compiled[0].body == "Typed text the disk never got.")
        #expect(pending.intent(for: page.id) == .save(page))

        // Once writes work again the next retry commits exactly that value.
        try FileManager.default.removeItem(at: root)
        #expect(pending.retry(using: store).isEmpty)
        #expect(pending.isEmpty)
        #expect(store.loadPages().pages.first { $0.id == page.id }?.body == "Typed text the disk never got.")
    }

    @Test func failedPinAndPromotionSavesAreStagedAndKeepTheirValues() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appendingPathComponent("wiki")
        try Data("blocked".utf8).write(to: root)
        let store = WikiStore(root: root)
        var pending = WikiPendingWrites()
        var page = samplePage()
        page.pinned = true
        #expect(pending.commit(page, using: store) != nil)
        let promoted = try WikiPromotion.promote(page, promotedBy: "tester", acknowledged: [], now: t1)
        #expect(pending.commit(promoted, using: store) != nil)
        // The newest value replaces the older one; nothing is dropped.
        #expect(pending.intent(for: page.id) == .save(promoted))
        try FileManager.default.removeItem(at: root)
        #expect(pending.retry(using: store).isEmpty)
        #expect(store.loadPages().pages.first?.scope == .global)
        #expect(store.loadPages().pages.first?.pinned == true)
    }

    @Test func aDirectSaveNeverBringsBackAPageWithAPendingDelete() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wiki-never-\(UUID().uuidString)")
        let page = samplePage()
        var pending = WikiPendingWrites()
        _ = pending.stage(replacing: [page], with: [])
        #expect(pending.commit(page, using: WikiStore(root: dir)) == nil)
        #expect(pending.intent(for: page.id) == .delete)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func failedDeleteIsRetainedAndNotOverwrittenByACompile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        let a = meeting("Planning", decisions: ["Ship it."])
        let page = try #require(WikiCompiler.compile(meetings: [a], into: [], now: t0).first)
        try store.save(page)

        var pending = WikiPendingWrites()
        var effective = [page]
        effective = pending.stage(replacing: effective, with: [])
        #expect(effective.isEmpty)
        #expect(pending.intent(for: page.id) == .delete)
        // A later compile that would bring the page back does not overwrite the pending delete.
        effective = pending.stage(replacing: effective, with: [page])
        #expect(effective.isEmpty)
        #expect(pending.overlaying(store.loadPages().pages).isEmpty)

        #expect(pending.retry(using: store).isEmpty)
        #expect(pending.isEmpty)
        #expect(store.loadPages().pages.isEmpty)
    }

    @Test func pausedLearningStillRemovesDeletedAndForgottenMeetings() {
        let a = meeting("Weekly sync 1", day: 0, decisions: ["Only in A."])
        let b = meeting("Weekly sync 2", day: 1, decisions: ["Only in B."])
        let pages = WikiCompiler.compile(meetings: [a, b], into: [], now: t0)

        // A was deleted while paused.
        let deleted = WikiCompiler.compile(meetings: [b], into: pages, ingest: false, now: t1)
        #expect(deleted.count == 1)
        #expect(!deleted[0].body.contains("Only in A."))
        #expect(deleted[0].body.contains("Only in B."))

        // B was forgotten while paused.
        let forgotten = WikiCompiler.compile(meetings: [a, b], into: pages, excluding: [b.id], ingest: false, now: t1)
        #expect(!forgotten[0].body.contains("Only in B."))
        #expect(forgotten[0].body.contains("Only in A."))

        // Paused: nothing new is learned, even from a meeting that is not in the pages yet.
        let c = meeting("Hiring loop", day: 2, decisions: ["New thing."])
        let paused = WikiCompiler.compile(meetings: [a, b, c], into: pages, ingest: false, now: t1)
        #expect(paused == pages)
        #expect(WikiCompiler.compile(meetings: [a, b, c], into: pages, now: t1).count == 2)
    }

    @Test func pausedDeletionHoldsThroughTheStore() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        let a = meeting("Planning", decisions: ["Only in A."])
        for page in WikiCompiler.compile(meetings: [a], into: [], now: t0) { try store.save(page) }
        try store.setLearningPaused(true)
        try store.forget(meetings: [a.id])

        let state = try store.loadState()
        let compiled = WikiCompiler.compile(
            meetings: [a], into: store.loadPages().pages, excluding: Set(state.forgottenMeetings),
            ingest: !state.learningPaused, now: t1
        )
        #expect(compiled.isEmpty)
        for page in store.loadPages().pages where !compiled.contains(where: { $0.id == page.id }) { try store.delete(id: page.id) }
        #expect(store.loadPages().pages.isEmpty)
    }

    @Test func interruptedResetKeepsLearningPausedWithHealthyFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        let id = UUID()
        try store.saveState(WikiStoreState(learningPaused: false, forgottenMeetings: [id]))
        // Torn journal line: recovery pauses learning.
        try Data("\(id.uuidString)\nnot-an-id".utf8).write(to: store.journalURL)
        #expect(store.loadStateRecovering().state.learningPaused)

        // Simulate an exit right after the first reset step (durable paused + marker) and the journal repair.
        try store.saveState(WikiStoreState(learningPaused: true, forgottenMeetings: [id], resetInProgress: true))
        try Data((id.uuidString + "\n").utf8).write(to: store.journalURL)
        let recovered = store.loadStateRecovering()
        #expect(recovered.state.learningPaused)
        #expect(recovered.error != nil)
        #expect(recovered.state.forgottenMeetings == [id])
        // Resuming is refused until a reset completes.
        #expect(throws: WikiStoreError.self) { try store.setLearningPaused(false) }

        // A completed reset clears the marker.
        let done = try store.resetState()
        #expect(!done.learningPaused && !done.resetInProgress)
        #expect(store.loadStateRecovering().error == nil)
        #expect(!(try store.loadState().resetInProgress))
    }

    @Test func participantNamesSkipGenericLabels() {
        let m = meeting("Sync", decisions: ["x"], participants: ["Speaker", "Speaker 2", "Dana Whitfield", "dana whitfield", "You"])
        #expect(WikiCompiler.participantNames(in: m) == ["Dana Whitfield"])
    }

    // MARK: Search and edit

    @Test func searchFiltersByEveryWordAndPinsFirst() {
        var alpha = WikiPage(id: "topic-alpha", title: "Alpha plan", body: "ship the beta", updatedAt: t0)
        let beta = WikiPage(id: "topic-beta", title: "Beta plan", body: "hire two people", updatedAt: t1)
        alpha.pinned = true
        let all = [beta, alpha]
        #expect(WikiSearch.filter(all, query: "").map(\.id) == ["topic-alpha", "topic-beta"])
        #expect(WikiSearch.filter(all, query: "PLAN beta").map(\.id) == ["topic-alpha", "topic-beta"])
        #expect(WikiSearch.filter(all, query: "hire").map(\.id) == ["topic-beta"])
        #expect(WikiSearch.filter(all, query: "nothing like this").isEmpty)
    }

    @Test func editingAGlobalPageMakesItPersonalAgain() throws {
        var page = try WikiPromotion.promote(samplePage(), promotedBy: "tester", acknowledged: [], now: t0)
        #expect(page.scope == .global)
        #expect(page.applyEdit(body: "Plain body.", now: t1) == false)
        #expect(page.scope == .global)
        #expect(page.applyEdit(body: "Different body.", now: t1) == true)
        #expect(page.scope == .personal)
        #expect(page.promotedBy == nil && page.promotedAt == nil)
        #expect(page.userEdited)
        #expect(page.updatedAt == t1)
    }

    @Test func markdownExportHasTitleAndBody() {
        #expect(samplePage(body: "Line").markdown() == "# Sample\n\nLine\n")
    }

    // MARK: Scanner

    private func substring(_ text: String, _ finding: SensitiveFinding) -> String {
        (text as NSString).substring(with: NSRange(location: finding.range.lowerBound, length: finding.range.count))
    }

    @Test func scannerFindsEmailWithRange() {
        let text = "Write to dana.w+test@example.co.uk today"
        let findings = SensitiveInfoScanner.scan(text)
        let email = findings.first { $0.kind == .email }
        #expect(email != nil)
        #expect(email.map { substring(text, $0) } == "dana.w+test@example.co.uk")
        #expect(email?.matched == "dana.w+test@example.co.uk")
        #expect(email.flatMap { $0.swiftRange(in: text) }.map { String(text[$0]) } == "dana.w+test@example.co.uk")
    }

    @Test func scannerFindsPhoneNumbers() {
        for number in ["+1 (415) 555-0132", "415-555-0132", "415.555.0132", "+44 20 7946 0958", "4155550132"] {
            #expect(kinds("Call \(number) tomorrow").contains(.phone), "\(number)")
        }
    }

    @Test func scannerIgnoresDatesCountsAndDecimals() {
        let text = "We shipped 12 items in 3 days on 2026-11-07 10 people came, pi is 3.14159265358"
        #expect(!kinds(text).contains(.phone))
        #expect(kinds("Nothing sensitive in this plain sentence.").isEmpty)
    }

    @Test func luhnChecksum() {
        #expect(SensitiveInfoScanner.isLuhnValid("4111111111111111"))
        #expect(SensitiveInfoScanner.isLuhnValid("5555555555554444"))
        #expect(SensitiveInfoScanner.isLuhnValid("378282246310005"))
        #expect(!SensitiveInfoScanner.isLuhnValid("4111111111111112"))
        #expect(!SensitiveInfoScanner.isLuhnValid("4111 1111"))
        #expect(!SensitiveInfoScanner.isLuhnValid("1"))
    }

    @Test func scannerFindsCardNumbersOnlyWhenLuhnPasses() {
        for number in ["4111 1111 1111 1111", "4111-1111-1111-1111", "4111111111111111", "5555 5555 5555 4444", "3782 822463 10005"] {
            #expect(kinds("Card \(number) on file").contains(.card), "\(number)")
        }
        #expect(!kinds("Card 4111 1111 1111 1112 on file").contains(.card))
        #expect(!kinds("Card 4111111111111112 on file").contains(.card))
        // A card number is not also reported as a phone number.
        #expect(!kinds("Card 4111 1111 1111 1111 on file").contains(.phone))
    }

    @Test func scannerFindsIBANsWithChecksum() {
        #expect(kinds("Pay GB82 WEST 1234 5698 7654 32.").contains(.iban))
        #expect(kinds("Pay DE89 3704 0044 0532 0130 00.").contains(.iban))
        #expect(kinds("Pay GB82WEST12345698765432.").contains(.iban))
        #expect(!kinds("Pay GB82 WEST 1234 5698 7654 33.").contains(.iban))
        #expect(SensitiveInfoScanner.isIBANValid("GB82WEST12345698765432"))
        #expect(!SensitiveInfoScanner.isIBANValid("GB82WEST12345698765433"))
    }

    @Test func scannerFindsEachSecretPattern() {
        let samples: [(String, String)] = [
            ("openai-style", "sk-" + String(repeating: "ab12", count: 6)),
            ("github", "ghp_" + String(repeating: "Ab1Cd2", count: 6)),
            ("slack", "xoxb-" + String(repeating: "1234", count: 4) + "-synthetic"),
            ("aws", "AKIAIOSFODNN7EXAMPLE"),
            ("hex", "0123456789abcdef0123456789abcdef01234567"),
            ("base64", "aB3dE6gH9jK2mN5pQ8sT1vW4yZ7bC0eF3hJ6kL9nP2rS5uV8"),
            ("jwt", "eyJhbGciOiJIUzI1" + "." + "eyJzdWIiOiJzeW50aGV0aWM" + "." + "c2lnbmF0dXJl"),
            ("bearer", "Bearer " + String(repeating: "q1w2e3r4", count: 3)),
            ("pem", "-----BEGIN RSA PRIVATE KEY-----"),
        ]
        for (name, secret) in samples {
            let text = "value: \(secret) end"
            let findings = SensitiveInfoScanner.scan(text)
            #expect(findings.contains { $0.kind == .secret }, "\(name)")
        }
    }

    @Test func scannerDoesNotFlagPathsOrSlugsAsSecrets() {
        #expect(!kinds("see /Users/tony/dev/zeus-wt/takeover-20261102-1834/notes").contains(.secret))
        #expect(!kinds("the-quick-brown-fox-jumps-over-the-lazy-dog-again-and-again").contains(.secret))
        #expect(!kinds("a short token like abc123 is fine").contains(.secret))
    }

    @Test func scannerFindsAddresses() {
        #expect(kinds("Meet at 12 Elm Street tomorrow").contains(.address))
        #expect(kinds("Office is 221 Baker St.").contains(.address))
        #expect(kinds("Ship to 4500 North Ocean Boulevard").contains(.address))
        #expect(kinds("Send it to P.O. Box 4471").contains(.address))
        #expect(!kinds("We have 3 ways to decide").contains(.address))
    }

    @Test func scannerFindsHealthAndFinanceTerms() {
        #expect(kinds("Her diagnosis and prescription changed").contains(.health))
        #expect(kinds("Talked about mental health days").contains(.health))
        #expect(kinds("The salary and mortgage numbers").contains(.finance))
        #expect(kinds("Wire to the bank account on Friday").contains(.finance))
        #expect(!kinds("We decided to ship on Friday").contains(.health))
        #expect(!kinds("Patientia is a virtue").contains(.health))
    }

    @Test func scannerFindsParticipantNames() {
        let text = "Dana Whitfield agreed. Later dana said the Annual plan is fine."
        let findings = SensitiveInfoScanner.scan(text, participantNames: ["Dana Whitfield", "Ann", "Speaker"])
        let names = findings.filter { $0.kind == .personName }
        #expect(names.map(\.matched) == ["Dana Whitfield", "dana"])
        #expect(names.map { substring(text, $0) } == ["Dana Whitfield", "dana"])
        // Without names given, a name is just a word.
        #expect(!kinds(text).contains(.personName))
    }

    @Test func findingsCarryAcknowledgementKeysAndRedaction() {
        let card = SensitiveInfoScanner.scan("Card 4111 1111 1111 1111 end").first { $0.kind == .card }
        #expect(card?.redacted == "41…11")
        #expect(card?.redacted.contains("1111 1111") == false)
        let a = SensitiveFinding(kind: .email, range: 0..<5, matched: "A@x.io")
        let b = SensitiveFinding(kind: .email, range: 20..<25, matched: "a@X.io")
        #expect(a.acknowledgementKey == b.acknowledgementKey)
        #expect(a.id != b.id)
    }

    @Test func overlappingFindingsOfOneKindAreCollapsed() {
        let secret = "ghp_" + String(repeating: "Ab1Cd2", count: 6)
        let findings = SensitiveInfoScanner.scan("token \(secret)").filter { $0.kind == .secret }
        #expect(findings.count == 1)
    }

    // MARK: Promotion

    private func blocked(_ attempt: () throws -> WikiPage) -> [SensitiveFinding]? {
        do {
            _ = try attempt()
            return nil
        } catch let error as WikiPromotionError {
            if case .blocked(let findings) = error { return findings }
            return nil
        } catch {
            return nil
        }
    }

    @Test func promotionIsBlockedByFindings() {
        let page = samplePage(body: "Contact dana@example.com about the 12 Elm Street office.")
        let findings = blocked { try WikiPromotion.promote(page, promotedBy: "tester", acknowledged: [], now: t1) }
        #expect(findings != nil)
        #expect(Set(findings?.map(\.kind) ?? []) == [.email, .address])
    }

    @Test func promotionNeedsEveryFindingAcknowledged() throws {
        let page = samplePage(body: "Contact dana@example.com about the 12 Elm Street office.")
        let all = WikiPromotion.findings(for: page)
        let emailKey = try #require(all.first { $0.kind == .email }).acknowledgementKey
        let partial = blocked { try WikiPromotion.promote(page, promotedBy: "tester", acknowledged: [emailKey], now: t1) }
        #expect(Set(partial?.map(\.kind) ?? []) == [.address])
        #expect(page.scope == .personal)

        let promoted = try WikiPromotion.promote(
            page, promotedBy: "tester", acknowledged: Set(all.map(\.acknowledgementKey)), now: t1
        )
        #expect(promoted.scope == .global)
    }

    @Test func promotionRecordsWhoAndWhen() throws {
        let promoted = try WikiPromotion.promote(samplePage(), promotedBy: "  tony  ", acknowledged: [], now: t1)
        #expect(promoted.scope == .global)
        #expect(promoted.promotedBy == "tony")
        #expect(promoted.promotedAt == t1)
        let back = WikiPromotion.demote(promoted)
        #expect(back.scope == .personal && back.promotedBy == nil && back.promotedAt == nil)
    }

    @Test func promotionNeedsAPromoterName() {
        #expect(throws: WikiPromotionError.missingPromoter) {
            _ = try WikiPromotion.promote(samplePage(), promotedBy: "   ", acknowledged: [], now: t1)
        }
    }

    @Test func promotionScansTheTitleAndParticipantNames() throws {
        var page = samplePage(body: "Ship it on Friday.")
        page.title = "Call with dana@example.com"
        #expect(blocked { try WikiPromotion.promote(page, promotedBy: "tester", acknowledged: [], now: t1) } != nil)

        let m = meeting("Planning", decisions: ["Dana Whitfield will send the budget."], participants: ["Dana Whitfield"])
        let compiled = WikiCompiler.compile(meetings: [m], into: [], now: t0)[0]
        let names = try #require(blocked { try WikiPromotion.promote(compiled, promotedBy: "tester", acknowledged: [], now: t1) })
        #expect(names.contains { $0.kind == .personName })
    }

    // MARK: Store

    @Test func storeRoundTripsPages() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir.appendingPathComponent("wiki", isDirectory: true))
        let m = meeting("Planning", decisions: ["Ship it."], actions: [("Lee will update the plan.", true)], participants: ["Dana Whitfield"])
        var pages = WikiCompiler.compile(meetings: [m], into: [], now: t0)
        pages[0].pinned = true
        pages.append(try WikiPromotion.promote(samplePage(id: "topic-global"), promotedBy: "tester", acknowledged: [], now: t1))
        for page in pages { try store.save(page) }

        let loaded = store.loadPages()
        #expect(loaded.failures.isEmpty)
        #expect(Set(loaded.pages.map(\.id)) == Set(pages.map(\.id)))
        for page in pages {
            #expect(loaded.pages.first { $0.id == page.id } == page)
        }
    }

    @Test func storeWritesOwnerOnlyFilesAtomically() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appendingPathComponent("wiki", isDirectory: true)
        let store = WikiStore(root: root)
        var page = samplePage()
        try store.save(page)
        page.body = "Second version."
        try store.save(page)
        try store.setLearningPaused(true)

        #expect(try permissions(root) == 0o700)
        #expect(try permissions(root.appendingPathComponent("topic-sample.json")) == 0o600)
        #expect(try permissions(store.stateURL) == 0o600)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        #expect(names == ["_state.json", "topic-sample.json"])
        #expect(store.loadPages().pages.first?.body == "Second version.")
    }

    @Test func storeSurfacesCorruptFilesAndKeepsTheRest() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        try store.save(samplePage())
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("broken.json"))

        let loaded = store.loadPages()
        #expect(loaded.pages.map(\.id) == ["topic-sample"])
        #expect(loaded.failures.count == 1)
        #expect(loaded.failures.first?.contains("broken.json") == true)
    }

    @Test func storeSurfacesAMismatchedPageID() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        try store.save(samplePage(id: "topic-a"))
        try FileManager.default.moveItem(at: dir.appendingPathComponent("topic-a.json"), to: dir.appendingPathComponent("topic-b.json"))
        let loaded = store.loadPages()
        #expect(loaded.pages.isEmpty)
        #expect(loaded.failures.first?.contains("topic-b.json") == true)
    }

    @Test func storeRefusesGlobalPagesWithoutAPromotionRecord() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        var page = samplePage()
        page.scope = .global
        #expect(throws: WikiStoreError.self) { try store.save(page) }
        #expect(store.loadPages().pages.isEmpty)

        // A hand-edited file that claims global scope is shown as personal, with a warning.
        try store.save(samplePage())
        let file = dir.appendingPathComponent("topic-sample.json")
        let edited = String(decoding: try Data(contentsOf: file), as: UTF8.self)
            .replacingOccurrences(of: "\"scope\" : \"personal\"", with: "\"scope\" : \"global\"")
        try Data(edited.utf8).write(to: file)
        let loaded = store.loadPages()
        #expect(loaded.pages.first?.scope == .personal)
        #expect(loaded.failures.count == 1)
    }

    @Test func storeRejectsUnsafePageIDs() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir.appendingPathComponent("wiki", isDirectory: true))
        for id in ["../escape", "a/b", ".hidden", "_state", "", "spa ce", "é"] {
            #expect(!WikiStore.isValidID(id), "\(id)")
            #expect(throws: WikiStoreError.self) { try store.save(samplePage(id: id)) }
        }
        #expect(throws: WikiStoreError.self) { try store.delete(id: "../escape") }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("escape.json").path))
    }

    @Test func storeDeletesPageFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        try store.save(samplePage())
        try store.delete(id: "topic-sample")
        try store.delete(id: "topic-sample")
        #expect(store.loadPages().pages.isEmpty)
    }

    @Test func missingFolderLoadsEmpty() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir.appendingPathComponent("never-created", isDirectory: true))
        let loaded = store.loadPages()
        #expect(loaded.pages.isEmpty && loaded.failures.isEmpty)
        #expect(try store.loadState() == WikiStoreState())
    }

    // MARK: Pause flag and forgotten meetings

    @Test func pauseFlagPersistsAcrossStores() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appendingPathComponent("wiki", isDirectory: true)
        #expect(try WikiStore(root: root).loadState().learningPaused == false)
        try WikiStore(root: root).setLearningPaused(true)
        #expect(try WikiStore(root: root).loadState().learningPaused == true)
        try WikiStore(root: root).setLearningPaused(false)
        #expect(try WikiStore(root: root).loadState().learningPaused == false)
    }

    @Test func forgottenMeetingsPersistWithoutDuplicates() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        let a = UUID()
        let b = UUID()
        try store.forget(meetings: [a])
        let state = try store.forget(meetings: [a, b])
        #expect(state.forgottenMeetings == [a, b])
        #expect(try store.loadState().forgottenMeetings == [a, b])
        try store.setLearningPaused(true)
        #expect(try store.loadState().forgottenMeetings == [a, b])
    }

    @Test func corruptStateIsSurfacedNotIgnored() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        try Data("{".utf8).write(to: store.stateURL)
        #expect(throws: WikiStoreError.self) { _ = try store.loadState() }
        #expect(throws: WikiStoreError.self) { try store.setLearningPaused(false) }
        // Forgetting still works (it goes to the journal) and leaves the unreadable file as it was.
        let id = UUID()
        let merged = try store.forget(meetings: [id])
        #expect(merged.forgottenMeetings == [id] && merged.learningPaused)
        #expect(String(decoding: try Data(contentsOf: store.stateURL), as: UTF8.self) == "{")
    }

    @Test func forgetSurvivesCorruptStateAndResetAcrossStores() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = UUID()
        let second = UUID()
        try Data("{".utf8).write(to: WikiStore(root: dir).stateURL)
        try WikiStore(root: dir).forget(meetings: [first])
        // A new process sees the tombstone and stays paused.
        let relaunched = WikiStore(root: dir).loadStateRecovering()
        #expect(relaunched.error != nil && relaunched.state.learningPaused)
        #expect(relaunched.state.forgottenMeetings == [first])
        try WikiStore(root: dir).forget(meetings: [second, first])
        let reset = try WikiStore(root: dir).resetState(now: t1)
        #expect(!reset.learningPaused && Set(reset.forgottenMeetings) == [first, second])
        let after = WikiStore(root: dir).loadStateRecovering()
        #expect(after.error == nil && Set(after.state.forgottenMeetings) == [first, second])
        #expect(permissionsOrNil(WikiStore(root: dir).journalURL) == 0o600)
    }

    private func permissionsOrNil(_ url: URL) -> Int? { try? permissions(url) }

    @Test func failedForgetWriteThrowsSoItIsNeverAcknowledged() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appendingPathComponent("wiki")
        try Data("blocked".utf8).write(to: root)
        #expect(throws: WikiStoreError.self) { try WikiStore(root: root).forget(meetings: [UUID()]) }
    }

    @Test func tornJournalLineKeepsLearningPausedUntilReset() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        let id = UUID()
        try store.forget(meetings: [id])
        let handle = try FileHandle(forWritingTo: store.journalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("1234-torn".utf8))
        try handle.close()
        let state = store.loadStateRecovering()
        #expect(state.error != nil && state.state.learningPaused && state.state.forgottenMeetings == [id])
        _ = try store.resetState(now: t1)
        #expect(store.loadStateRecovering().error == nil)
        #expect(store.loadStateRecovering().state.forgottenMeetings == [id])
    }

    @Test func resetCopiesTheUnreadableFileAndNeverLeavesNoStateFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        try Data("{".utf8).write(to: store.stateURL)
        // The settings file is replaced in place (never moved away), so an interrupted reset can't read as
        // "no file, not paused". Before the replacement commits, the unreadable original is what a relaunch sees.
        let before = store.loadStateRecovering()
        #expect(before.error != nil && before.state.learningPaused)
        _ = try store.resetState(now: t1)
        let backup = dir.appendingPathComponent("_state.corrupt-\(Int(t1.timeIntervalSince1970)).json")
        #expect(String(decoding: try Data(contentsOf: backup), as: UTF8.self) == "{")
        #expect(FileManager.default.fileExists(atPath: store.stateURL.path))
        #expect(store.loadStateRecovering().error == nil)
    }

    @Test func corruptStateFailsClosedButKeepsReadableForgottenMeetings() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        let forgotten = UUID()

        // A wrongly typed field makes the file undecodable, but the forgotten ids are still readable.
        try Data(#"{"learningPaused": "yes", "forgottenMeetings": ["\#(forgotten.uuidString)", "not-a-uuid"]}"#.utf8).write(to: store.stateURL)
        let recovered = store.loadStateRecovering()
        #expect(recovered.error != nil)
        #expect(recovered.state.learningPaused)
        #expect(recovered.state.forgottenMeetings == [forgotten])

        // Not even JSON: nothing can be read, learning stays paused, and the error is still surfaced.
        try Data("{".utf8).write(to: store.stateURL)
        let unreadable = store.loadStateRecovering()
        #expect(unreadable.error != nil && unreadable.state.learningPaused && unreadable.state.forgottenMeetings.isEmpty)

        // A healthy file is returned as it is, with no error.
        try store.saveState(WikiStoreState(learningPaused: false, forgottenMeetings: [forgotten]))
        let healthy = store.loadStateRecovering()
        #expect(healthy.error == nil && !healthy.state.learningPaused && healthy.state.forgottenMeetings == [forgotten])
    }

    @Test func resetStateKeepsTheOldFileAndEveryForgottenMeeting() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        let readable = UUID()
        let sinceCorruption = UUID()
        let corrupt = #"{"learningPaused": 3, "forgottenMeetings": ["\#(readable.uuidString)"]}"#
        try Data(corrupt.utf8).write(to: store.stateURL)

        let state = try store.resetState(forgetting: [sinceCorruption, readable], now: t1)
        #expect(!state.learningPaused)
        #expect(state.forgottenMeetings == [readable, sinceCorruption])
        #expect(try store.loadState() == state)
        #expect(try permissions(store.stateURL) == 0o600)
        let backup = dir.appendingPathComponent("_state.corrupt-\(Int(t1.timeIntervalSince1970)).json")
        #expect(String(decoding: try Data(contentsOf: backup), as: UTF8.self) == corrupt)
        // Settings and backup files are never loaded as pages, and the toggle works again.
        #expect(store.loadPages().pages.isEmpty && store.loadPages().failures.isEmpty)
        try store.setLearningPaused(true)
        #expect(try store.loadState().forgottenMeetings == [readable, sinceCorruption])
    }

    @Test func deletionStillRunsWhileSettingsAreUnreadableAndIngestionStaysOff() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        let a = meeting("Weekly sync 1", day: 0, decisions: ["Only in A."])
        let b = meeting("Weekly sync 2", day: 1, decisions: ["Only in B."])
        let c = meeting("Hiring loop", day: 2, decisions: ["New thing."])
        let pages = WikiCompiler.compile(meetings: [a, b], into: [], now: t0)
        try Data(#"{"forgottenMeetings": "oops", "learningPaused": false}"#.utf8).write(to: store.stateURL)

        let state = store.loadStateRecovering()
        #expect(state.error != nil)
        // The fail-closed state still removes a deleted meeting (A is gone) and ingests nothing new (C).
        let compiled = WikiCompiler.compile(
            meetings: [b, c], into: pages, excluding: Set(state.state.forgottenMeetings), ingest: !state.state.learningPaused, now: t1
        )
        #expect(compiled.count == 1)
        #expect(!compiled[0].body.contains("Only in A.") && compiled[0].body.contains("Only in B."))
        // A meeting forgotten while the file is unreadable is honored from memory too.
        let forgotAfter = WikiCompiler.compile(meetings: [b, c], into: compiled, excluding: [b.id], ingest: false, now: t1)
        #expect(forgotAfter.isEmpty)
    }

    @Test func stateFileIsNotLoadedAsAPage() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WikiStore(root: dir)
        try store.setLearningPaused(true)
        let loaded = store.loadPages()
        #expect(loaded.pages.isEmpty && loaded.failures.isEmpty)
    }
}
