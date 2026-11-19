import Foundation
import Testing
@testable import ZeusCore

@Suite("Scribe Memory logic")
struct ScribeMemoryLogicTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.firstWeekday = 2 // Monday
        return calendar
    }

    /// Wednesday 2026-11-11 12:00 UTC.
    private var now: Date { Date(timeIntervalSince1970: 1_794_398_400) }

    private func days(_ count: Double, hours: Double = 0) -> Date {
        now.addingTimeInterval(-(count * 86_400) - hours * 3_600)
    }

    private func segment(_ id: String, _ speaker: ScribeSpeaker, _ start: TimeInterval, _ end: TimeInterval,
                         _ text: String = "words") -> ScribeTranscriptSegment {
        ScribeTranscriptSegment(id: id, session: ScribeSessionID(), speaker: speaker, start: start, end: end,
                                text: text, isFinal: true)
    }

    // MARK: Grouping

    @Test func bucketsTodayThisWeekAndEarlier() {
        #expect(ScribeMemoryGrouping.bucket(for: days(0, hours: 3), now: now, calendar: calendar) == .today)
        #expect(ScribeMemoryGrouping.bucket(for: days(1), now: now, calendar: calendar) == .thisWeek)  // Tuesday
        #expect(ScribeMemoryGrouping.bucket(for: days(2), now: now, calendar: calendar) == .thisWeek)  // Monday
        #expect(ScribeMemoryGrouping.bucket(for: days(3), now: now, calendar: calendar) == .earlier)   // last Sunday
        #expect(ScribeMemoryGrouping.bucket(for: days(40), now: now, calendar: calendar) == .earlier)
    }

    @Test func aDateInTheFutureCountsAsToday() {
        let later = now.addingTimeInterval(5 * 86_400)
        #expect(ScribeMemoryGrouping.bucket(for: later, now: now, calendar: calendar) == .today)
    }

    @Test func sectionsAreOrderedNewestFirstAndOmitEmptyGroups() {
        let entries: [(id: Int, date: Date)] = [
            (1, days(10)), (2, days(0, hours: 5)), (3, days(0, hours: 1)), (4, days(40)),
        ]
        let sections = ScribeMemoryGrouping.sections(entries, now: now, calendar: calendar)
        #expect(sections.map(\.bucket) == [.today, .earlier])
        #expect(sections[0].ids == [3, 2])
        #expect(sections[1].ids == [1, 4])
    }

    @Test func equalDatesKeepTheInputOrder() {
        let date = days(0, hours: 2)
        let sections = ScribeMemoryGrouping.sections([(id: "a", date: date), (id: "b", date: date)],
                                                     now: now, calendar: calendar)
        #expect(sections.first?.ids == ["a", "b"])
    }

    @Test func noMeetingsMakeNoSections() {
        let sections = ScribeMemoryGrouping.sections([(id: Int, date: Date)](), now: now, calendar: calendar)
        #expect(sections.isEmpty)
    }

    @Test func bucketTitles() {
        #expect(ScribeMemoryBucket.allCases.map(\.title) == ["Today", "This week", "Earlier"])
    }

    // MARK: Initials

    @Test func initialsUseTheFirstAndLastWord() {
        #expect(ScribeInitials.of("Marie Dubois") == "MD")
        #expect(ScribeInitials.of("jean luc picard") == "JP")
        #expect(ScribeInitials.of("Marie") == "M")
        #expect(ScribeInitials.of("Speaker 2") == "S2")
        #expect(ScribeInitials.of("  ") == "?")
        #expect(ScribeInitials.of("(Guest) Ana") == "GA")
    }

    // MARK: Talk time share

    @Test func peopleAreOrderedByTalkTimeWithPercentages() {
        let segments = [
            segment("1", .you, 0, 10),
            segment("2", .participant("Marie Dubois"), 10, 40),
            segment("3", .participant("Ben Lee"), 40, 50),
        ]
        let people = ScribeMemoryPeople.people(segments: segments)
        #expect(people.map(\.name) == ["Marie Dubois", "You", "Ben Lee"])
        #expect(people.map(\.percent) == [60, 20, 20])
        #expect(people.first?.initials == "MD")
        #expect(abs(people.reduce(0) { $0 + $1.share } - 1) < 0.0001)
    }

    @Test func peopleWithEqualTalkTimeKeepTheirFirstSpokenOrder() {
        let segments = [segment("1", .participant("Ben Lee"), 0, 10), segment("2", .you, 10, 20)]
        #expect(ScribeMemoryPeople.people(segments: segments).map(\.name) == ["Ben Lee", "You"])
    }

    @Test func emptyTranscriptHasNoPeople() {
        #expect(ScribeMemoryPeople.people(segments: []).isEmpty)
        #expect(ScribeMemoryPeople.people(segments: [segment("1", .you, 0, 5, "   ")]).isEmpty)
    }

    // MARK: Outcome line

    @Test func outcomePrefersADecisionThenAnOpenActionThenTheSummary() {
        var notes = ScribeMeetingNotes(summary: "We met.", decisions: ["Ship on Friday"],
                                       actionItems: [ScribeActionItem(text: "Send the deck")])
        #expect(ScribeMemoryOutcome.line(notes) == "Ship on Friday")
        notes.decisions = []
        #expect(ScribeMemoryOutcome.line(notes) == "Send the deck")
        notes.actionItems[0].done = true
        #expect(ScribeMemoryOutcome.line(notes) == "We met.")
        notes.summary = ""
        #expect(ScribeMemoryOutcome.line(notes) == "No summary.")
    }

    @Test func firstOpenActionSkipsTickedItems() {
        let notes = ScribeMeetingNotes(actionItems: [
            ScribeActionItem(text: "Done already", done: true), ScribeActionItem(text: "Call Ana"),
        ])
        #expect(ScribeMemoryOutcome.firstOpenAction(notes) == "Call Ana")
        #expect(ScribeMemoryOutcome.firstOpenAction(ScribeMeetingNotes()) == nil)
    }

    @Test func clipCollapsesWhiteSpaceAndCutsLongText() {
        #expect(ScribeMemoryOutcome.clip("a  b\n c", limit: 20) == "a b c")
        let long = String(repeating: "word ", count: 40)
        let clipped = ScribeMemoryOutcome.clip(long, limit: 30)
        #expect(clipped.count <= 30)
        #expect(clipped.hasSuffix("\u{2026}"))
    }

    @Test func durationLabels() {
        #expect(ScribeMemoryOutcome.durationLabel(20) == "Under a minute")
        #expect(ScribeMemoryOutcome.durationLabel(42 * 60) == "42 min")
        #expect(ScribeMemoryOutcome.durationLabel(65 * 60) == "1 h 5 min")
        #expect(ScribeMemoryOutcome.durationLabel(2 * 3600) == "2 h")
        #expect(ScribeMemoryOutcome.durationLabel(.nan) == "Under a minute")
    }

    // MARK: Search

    private var fields: ScribeMemoryFields {
        ScribeMemoryFields(title: "Pricing review", summary: "We discussed the Q4 budget.",
                           decisions: ["Keep the price"], actionItems: ["Send the proposal"],
                           people: ["You", "Marie Dubois"], transcript: "Let us look at the numbers.")
    }

    @Test func searchNeedsEveryWordAndIgnoresCaseAndAccents() {
        #expect(ScribeMemoryQuery(text: "budget q4").matches(fields))
        #expect(ScribeMemoryQuery(text: "BUDGET").matches(fields))
        #expect(!ScribeMemoryQuery(text: "budget hiring").matches(fields))
        #expect(ScribeMemoryQuery(text: "marié").matches(fields))
        #expect(ScribeMemoryQuery(text: "numbers").matches(fields))
    }

    @Test func personFilterNeedsThatPersonInTheMeeting() {
        #expect(ScribeMemoryQuery(people: ["marie dubois"]).matches(fields))
        #expect(!ScribeMemoryQuery(people: ["Ben Lee"]).matches(fields))
        #expect(!ScribeMemoryQuery(text: "budget", people: ["Ben Lee"]).matches(fields))
        #expect(ScribeMemoryQuery(text: "budget", people: ["You", "Marie Dubois"]).matches(fields))
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(ScribeMemoryQuery().isEmpty)
        #expect(ScribeMemoryQuery(text: "  ").isEmpty)
        #expect(!ScribeMemoryQuery(people: ["Ana"]).isEmpty)
        #expect(ScribeMemoryQuery().matches(fields))
    }

    @Test func filterChoicesAreUniqueInFirstSeenOrder() {
        let names = ScribeMemoryQuery.filterChoices([["You", "Marie Dubois"], ["marie dubois", "Ben Lee"], []])
        #expect(names == ["You", "Marie Dubois", "Ben Lee"])
    }
}
