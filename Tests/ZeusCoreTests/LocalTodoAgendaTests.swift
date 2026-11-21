import Foundation
import Testing
@testable import ZeusCore

/// Synthetic tasks and events only. Nothing here reads a calendar, a reminder list, or another app.
@Suite("Local to-do and agenda")
struct LocalTodoAgendaTests {
    private let zone = TimeZone(identifier: "America/New_York")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let now = LocalTodoAgendaTests.instant(2026, 11, 21, 10, 0, zone: "America/New_York")

    private static func instant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, zone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func allowed() -> LocalAccessPair { LocalAccessPair(events: .allowed, reminders: .allowed) }

    private func machine(access: LocalAccessPair? = nil, enabled: Bool = false) -> LocalTodoAgendaMachine {
        var value = LocalTodoAgendaMachine()
        if let access {
            value = value.reduce(.refresh(access), now: now, timeZone: zone).0
        }
        if enabled {
            value = value.reduce(.setEnabled(true), now: now, timeZone: zone).0
        }
        return value
    }

    private func todo(
        _ title: String,
        id: String? = nil,
        due: Date? = nil,
        allDay: Bool = true,
        list: String = "Tasks",
        source: String = "Exchange",
        kind: String = "exchange",
        zone: String = "America/New_York",
        completed: Bool = false
    ) -> LocalTodoRecord {
        LocalTodoRecord(
            id: id ?? title,
            title: title,
            listName: list,
            sourceName: source,
            sourceKind: kind,
            due: due,
            isAllDay: allDay,
            timeZoneIdentifier: zone,
            completed: completed)
    }

    private func event(
        _ title: String,
        start: Date,
        end: Date,
        id: String? = nil,
        series: String? = nil,
        allDay: Bool = false,
        calendar: String = "Calendar",
        source: String = "Exchange",
        kind: String = "exchange",
        zone: String = "America/New_York",
        recurring: Bool = false
    ) -> LocalAgendaRecord {
        LocalAgendaRecord(
            id: id ?? "\(title)-\(start.timeIntervalSinceReferenceDate)",
            seriesID: series ?? id ?? title,
            title: title,
            calendarName: calendar,
            sourceName: source,
            sourceKind: kind,
            start: start,
            end: end,
            isAllDay: allDay,
            timeZoneIdentifier: zone,
            isRecurring: recurring)
    }

    private func snapshot(
        todos: [LocalTodoRecord] = [],
        agenda: [LocalAgendaRecord] = [],
        sources: [String] = ["Exchange"],
        outlook: Bool = true,
        toDo: Bool = true
    ) -> LocalMicrosoftSnapshot {
        LocalMicrosoftSnapshot(
            todos: todos,
            agenda: agenda,
            presence: LocalAppPresence(outlookInstalled: outlook, toDoInstalled: toDo, microsoftSources: sources))
    }

    private func presented(_ snapshot: LocalMicrosoftSnapshot, at now: Date? = nil, zone: TimeZone? = nil) -> LocalTodoAgendaPhase {
        LocalTodoAgendaArrange.phase(for: snapshot, now: now ?? self.now, timeZone: zone ?? self.zone)
    }

    private func lines(_ phase: LocalTodoAgendaPhase) -> (todos: [LocalTodoLine], agenda: [LocalAgendaLine]) {
        guard case .populated(let view) = phase else { return ([], []) }
        return (view.todos, view.agenda)
    }

    // MARK: Setting and access

    @Test func theSettingIsOffUntilTurnedOn() {
        #expect(LocalTodoAgendaSetting.id == "todo.microsoftLocal")
        #expect(LocalTodoAgendaSetting.defaultEnabled == false)
        let fresh = LocalTodoAgendaMachine()
        #expect(fresh.phase == .off)
        #expect(fresh.enabled == false)
        let stayed = fresh.reduce(.refresh(allowed()), now: now, timeZone: zone)
        #expect(stayed.0.phase == .off)
        #expect(stayed.1.isEmpty)
    }

    @Test func theCatalogKeepsTheSwitchOffAndHidden() throws {
        let catalog = try repoText("Sources/Zeus/App/SettingsCatalog.swift")
        let line = catalog.split(separator: "\n").first { $0.contains("id: \"\(LocalTodoAgendaSetting.id)\"") }
        let row = try #require(line.map(String.init))
        #expect(row.contains("defaultValue: \"false\""))
        #expect(row.contains("state: .stub"))
        let generator = try repoText("scripts/gen-settings-catalog.py")
        #expect(generator.contains("'\(LocalTodoAgendaSetting.id)'"))
        #expect(generator.contains("todo.microsoftLocal stays off and hidden"))
    }

    @Test func accessMapsAReadGrantAndTreatsWriteOnlyAsDenied() {
        #expect(LocalAccessStatus.map(fullAccess: true, writeOnly: false, denied: false, restricted: false) == .allowed)
        #expect(LocalAccessStatus.map(fullAccess: true, writeOnly: true, denied: true, restricted: false) == .allowed)
        #expect(LocalAccessStatus.map(fullAccess: true, writeOnly: false, denied: false, restricted: true) == .restricted)
        #expect(LocalAccessStatus.map(fullAccess: false, writeOnly: true, denied: false, restricted: false) == .denied)
        #expect(LocalAccessStatus.map(fullAccess: false, writeOnly: false, denied: true, restricted: false) == .denied)
        #expect(LocalAccessStatus.map(fullAccess: false, writeOnly: false, denied: false, restricted: false) == .notAsked)
    }

    @Test func aMicrosoftAccountIsTheExchangeKindOrAnOutlookName() {
        #expect(MicrosoftAccountMatch.isMicrosoft(sourceName: "Outlook", sourceKind: "local"))
        #expect(MicrosoftAccountMatch.isMicrosoft(sourceName: "Exchange", sourceKind: "calDAV"))
        #expect(MicrosoftAccountMatch.isMicrosoft(sourceName: "Exchange Work", sourceKind: "local"))
        #expect(MicrosoftAccountMatch.isMicrosoft(sourceName: "outlook calendar", sourceKind: "calDAV"))
        #expect(MicrosoftAccountMatch.isMicrosoft(sourceName: "Work", sourceKind: "exchange"))
        #expect(MicrosoftAccountMatch.isMicrosoft(sourceName: "Work", sourceKind: "EXCHANGE"))
        #expect(!MicrosoftAccountMatch.isMicrosoft(sourceName: "iCloud", sourceKind: "calDAV"))
        #expect(!MicrosoftAccountMatch.isMicrosoft(sourceName: "On My Mac", sourceKind: "local"))
        #expect(!MicrosoftAccountMatch.isMicrosoft(sourceName: "My outlook notes", sourceKind: "local"))
    }

    // MARK: State machine

    @Test func turningOnAsksOnlyWhenNothingIsReadableYet() {
        let asking = LocalTodoAgendaMachine().reduce(.setEnabled(true), now: now, timeZone: zone)
        #expect(asking.0.phase == .permissionNeeded)
        #expect(asking.0.enabled)
        #expect(asking.1 == [.requestAccess])

        let denied = machine(access: LocalAccessPair(events: .denied, reminders: .restricted))
            .reduce(.setEnabled(true), now: now, timeZone: zone)
        #expect(denied.0.phase == .denied(LocalAccessPair(events: .denied, reminders: .restricted)))
        #expect(denied.1.isEmpty)

        let readable = machine(access: LocalAccessPair(events: .restricted, reminders: .allowed))
            .reduce(.setEnabled(true), now: now, timeZone: zone)
        #expect(readable.0.phase == .loading)
        #expect(readable.1 == [.read(generation: 1)])
    }

    @Test func aPermissionAnswerWhileOffDoesNotRead() {
        let answered = LocalTodoAgendaMachine().reduce(.permission(allowed()), now: now, timeZone: zone)
        #expect(answered.0.phase == .off)
        #expect(answered.0.enabled == false)
        #expect(answered.0.access == allowed())
        #expect(answered.1.isEmpty)
        let on = answered.0.reduce(.setEnabled(true), now: now, timeZone: zone)
        #expect(on.0.phase == .loading)
        #expect(on.1 == [.read(generation: 1)])
    }

    @Test func denialReplacesTheAskAndALaterGrantReads() {
        let asking = LocalTodoAgendaMachine().reduce(.setEnabled(true), now: now, timeZone: zone).0
        let denied = asking.reduce(.permission(LocalAccessPair(events: .denied, reminders: .notAsked)), now: now, timeZone: zone)
        #expect(denied.0.phase == .permissionNeeded)
        #expect(denied.1 == [.requestAccess])
        let bothDenied = denied.0.reduce(.permission(LocalAccessPair(events: .denied, reminders: .denied)), now: now, timeZone: zone)
        #expect(bothDenied.0.phase == .denied(LocalAccessPair(events: .denied, reminders: .denied)))
        #expect(bothDenied.1.isEmpty)
        let granted = bothDenied.0.reduce(.permission(allowed()), now: now, timeZone: zone)
        #expect(granted.0.phase == .loading)
        #expect(granted.1 == [.read(generation: 1)])
    }

    @Test func aStaleLoadCannotReviveATurnedOffRead() {
        let loading = machine(access: allowed(), enabled: true)
        #expect(loading.phase == .loading)
        #expect(loading.generation == 1)
        let off = loading.reduce(.setEnabled(false), now: now, timeZone: zone)
        #expect(off.0.phase == .off)
        #expect(off.0.enabled == false)
        #expect(off.1.isEmpty)
        let late = off.0.reduce(.loaded(generation: 1, snapshot(todos: [todo("Buy milk")])), now: now, timeZone: zone)
        #expect(late.0.phase == .off)
        let failed = off.0.reduce(.failed(generation: 1, .readFailed), now: now, timeZone: zone)
        #expect(failed.0.phase == .off)
    }

    @Test func aMatchingFailureIsTheErrorPhaseAndRefreshTriesAgain() {
        let loading = machine(access: allowed(), enabled: true)
        let failed = loading.reduce(.failed(generation: 1, .readFailed), now: now, timeZone: zone)
        #expect(failed.0.phase == .error(.readFailed))
        #expect(failed.1.isEmpty)
        let again = failed.0.reduce(.refresh(allowed()), now: now, timeZone: zone)
        #expect(again.0.phase == .loading)
        #expect(again.1 == [.read(generation: 2)])
    }

    @Test func loadedResultsFollowTheSnapshot() {
        let loading = machine(access: allowed(), enabled: true)
        let missingApps = loading.reduce(.loaded(generation: 1, snapshot(sources: [], outlook: false, toDo: false)), now: now, timeZone: zone)
        #expect(missingApps.0.phase == .missingApp(.applicationsNotInstalled))
        let missingAccount = loading.reduce(.loaded(generation: 1, snapshot(sources: [], outlook: true, toDo: false)), now: now, timeZone: zone)
        #expect(missingAccount.0.phase == .missingApp(.notInMacAccounts))
        let empty = loading.reduce(.loaded(generation: 1, snapshot()), now: now, timeZone: zone)
        #expect(empty.0.phase == .empty)
        let filled = loading.reduce(.loaded(generation: 1, snapshot(todos: [todo("Buy milk")])), now: now, timeZone: zone)
        #expect(lines(filled.0.phase).todos.map(\.title) == ["Buy milk"])
    }

    @Test func everyPhaseAndEffectHasAName() {
        let phases: [LocalTodoAgendaPhase] = [
            .off, .permissionNeeded, .denied(allowed()), .loading,
            .missingApp(.applicationsNotInstalled), .missingApp(.notInMacAccounts),
            .empty, .populated(LocalTodoAgendaView(todos: [], agenda: [])), .error(.readFailed),
        ]
        let names = phases.map { phase -> String in
            switch phase {
            case .off: "off"
            case .permissionNeeded: "permissionNeeded"
            case .denied: "denied"
            case .loading: "loading"
            case .missingApp: "missingApp"
            case .empty: "empty"
            case .populated: "populated"
            case .error: "error"
            }
        }
        #expect(names.count == 9)
        let effects: [LocalTodoAgendaEffect] = [.requestAccess, .read(generation: 4)]
        for effect in effects {
            switch effect {
            case .requestAccess, .read: break
            }
        }
    }

    // MARK: Boundaries

    @Test func allDayEndsOnTheNextMorningAndDoesNotSpillIntoIt() {
        let start = Self.instant(2026, 11, 21, 0, 0, zone: "America/New_York")
        let end = Self.instant(2026, 11, 22, 0, 0, zone: "America/New_York")
        let item = event("Focus", start: start, end: end, allDay: true)
        let today = presented(snapshot(agenda: [item]))
        #expect(lines(today).agenda.map(\.when) == ["All day"])
        let tomorrowMorning = Self.instant(2026, 11, 22, 0, 30, zone: "America/New_York")
        let next = presented(snapshot(agenda: [item]), at: tomorrowMorning)
        #expect(next == .empty)
    }

    @Test func aMultiDayEventStaysOneRowOnEachDayItCovers() {
        let start = Self.instant(2026, 11, 20, 0, 0, zone: "America/New_York")
        let end = Self.instant(2026, 11, 23, 0, 0, zone: "America/New_York")
        let item = event("Offsite", start: start, end: end, allDay: true)
        let phase = presented(snapshot(agenda: [item]))
        #expect(lines(phase).agenda.map(\.when) == ["All day · 3 days"])
        #expect(lines(phase).agenda.count == 1)
    }

    @Test func aTimedEventKeepsItsOwnZone() {
        let start = Self.instant(2026, 11, 21, 7, 0, zone: "America/Los_Angeles")
        let end = Self.instant(2026, 11, 21, 8, 0, zone: "America/Los_Angeles")
        let item = event("Standup", start: start, end: end, zone: "America/Los_Angeles")
        let phase = presented(snapshot(agenda: [item]))
        #expect(lines(phase).agenda.map(\.when) == ["07:00–08:00 · Los Angeles"])
    }

    @Test func daylightSavingDoesNotDuplicateOrDropTheDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let spring = DateComponents(year: 2026, month: 3, day: 8, hour: 2, minute: 30)
        let resolved = calendar.date(from: spring)!
        #expect(calendar.component(.hour, from: resolved) != 2)
        #expect(calendar.component(.day, from: resolved) == 8)
        let springEnd = calendar.date(byAdding: .hour, value: 1, to: resolved)!
        let springItem = event("Gap", start: resolved, end: springEnd)
        let springDay = Self.instant(2026, 3, 8, 12, 0, zone: "America/New_York")
        #expect(lines(presented(snapshot(agenda: [springItem]), at: springDay)).agenda.count == 1)

        let allDayStart = Self.instant(2026, 11, 1, 0, 0, zone: "America/New_York")
        let allDayEnd = Self.instant(2026, 11, 2, 0, 0, zone: "America/New_York")
        let folded = Self.instant(2026, 11, 1, 1, 30, zone: "America/New_York")
        let foldedAgain = folded.addingTimeInterval(3600)
        let fallNow = Self.instant(2026, 11, 1, 12, 0, zone: "America/New_York")
        let fall = presented(snapshot(agenda: [
            event("Holiday", start: allDayStart, end: allDayEnd, allDay: true),
            event("Once", start: folded, end: folded.addingTimeInterval(1800), series: "fold"),
            event("Once", start: foldedAgain, end: foldedAgain.addingTimeInterval(1800), series: "fold"),
        ]), at: fallNow)
        let agenda = lines(fall).agenda
        #expect(agenda.filter { $0.when == "All day" }.count == 1)
        #expect(agenda.filter { $0.when.contains("01:30") }.count == 2)
    }

    @Test func recurringOccurrencesStayDistinctAndARepeatedInstantCollapses() {
        let first = Self.instant(2026, 11, 21, 9, 0, zone: "America/New_York")
        let second = Self.instant(2026, 11, 22, 9, 0, zone: "America/New_York")
        let series = [
            event("Weekly", start: first, end: first.addingTimeInterval(3600), series: "weekly", recurring: true),
            event("Weekly", start: second, end: second.addingTimeInterval(3600), series: "weekly", recurring: true),
            event("Weekly", start: first, end: first.addingTimeInterval(3600), id: "copy", series: "weekly", recurring: true),
        ]
        let today = lines(presented(snapshot(agenda: series))).agenda
        #expect(today.map(\.title) == ["Weekly"])
        let both = LocalTodoAgendaArrange.agenda(series, now: now, timeZone: zone, windowed: false)
        #expect(both.count == 2)
        #expect(both.map(\.start) == [first, second])
    }

    @Test func zeroItemsAreEmptyAndAThousandStayInOrder() {
        #expect(presented(snapshot()) == .empty)
        let todos = (0..<1000).map { todo(String(format: "Task %04d", $0), id: "t\($0)") }
        let phase = presented(snapshot(todos: todos))
        let titles = lines(phase).todos.map(\.title)
        #expect(titles.count == 1000)
        #expect(titles.first == "Task 0000")
        #expect(titles.last == "Task 0999")
        #expect(titles == titles.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test func unicodeTitlesSurviveAndCombiningMarksDedupe() throws {
        let composed = "Café"
        let decomposed = "Cafe\u{0301}"
        let phase = presented(snapshot(todos: [
            todo(composed, id: "a"),
            todo(decomposed, id: "b"),
            todo("東京の予定", id: "c"),
            todo("🎉 Ship", id: "d"),
        ]))
        let titles = lines(phase).todos.map(\.title)
        let cafe = try #require(titles.filter { $0.precomposedStringWithCanonicalMapping == composed.precomposedStringWithCanonicalMapping }.first)
        #expect(titles.count == 3)
        // Swift compares these as equal, so the kept scalars show which spelling survived.
        #expect(cafe.unicodeScalars.elementsEqual(composed.unicodeScalars))
        #expect(!cafe.unicodeScalars.elementsEqual(decomposed.unicodeScalars))
        #expect(titles.contains("東京の予定"))
        #expect(titles.contains("🎉 Ship"))
    }

    @Test func completedAndForeignItemsAreLeftOut() {
        let phase = presented(snapshot(
            todos: [todo("Done", completed: true), todo("Home", source: "iCloud", kind: "calDAV")],
            agenda: [event("Birthday", start: now, end: now.addingTimeInterval(3600), source: "iCloud", kind: "local")],
            sources: []))
        #expect(phase == .missingApp(.notInMacAccounts))
        let kept = presented(snapshot(todos: [todo("Done", completed: true), todo("Open")]))
        #expect(lines(kept).todos.map(\.title) == ["Open"])
    }

    @Test func dueLabelsUseTheInjectedDay() {
        let yesterday = Self.instant(2026, 11, 20, 9, 0, zone: "America/New_York")
        let later = Self.instant(2026, 11, 21, 17, 0, zone: "America/New_York")
        let future = Self.instant(2026, 12, 2, 9, 0, zone: "America/New_York")
        let phase = presented(snapshot(todos: [
            todo("Late", id: "late", due: yesterday, allDay: false),
            todo("Standup", id: "today", due: later, allDay: false),
            todo("Someday", id: "none"),
            todo("December", id: "later", due: future, allDay: false),
        ]))
        let labels = Dictionary(uniqueKeysWithValues: lines(phase).todos.map { ($0.title, $0.dueLabel) })
        #expect(labels["Late"] == "Overdue")
        #expect(labels["Standup"] == "Today 17:00")
        #expect(labels["Someday"] == "No date")
        #expect(labels["December"] == "2 Dec 09:00")
    }

    // MARK: Property

    @Test func dedupeAndSortAreIdempotent() {
        var rng = SplitMix64(seed: 0xC0FFEE)
        for _ in 0..<80 {
            let count = Int(rng.next() % 40)
            var records: [LocalAgendaRecord] = []
            for index in 0..<count {
                let day = Int(rng.next() % 7) - 2
                let hour = Int(rng.next() % 24)
                let start = Self.instant(2026, 11, 21, 0, 0, zone: "America/New_York").addingTimeInterval(Double(day * 86_400 + hour * 3_600))
                let title = ["Café", "東京", "🎉", "Review", "1:1"][Int(rng.next() % 5)]
                let kind = rng.next() % 2 == 0 ? "exchange" : "calDAV"
                records.append(event(
                    title,
                    start: start,
                    end: start.addingTimeInterval(Double(1_800 + Int(rng.next() % 7_200))),
                    id: "r\(index)",
                    series: "s\(rng.next() % 8)",
                    allDay: rng.next() % 5 == 0,
                    kind: kind,
                    recurring: true))
                if rng.next() % 3 == 0, let last = records.last {
                    var copy = last
                    copy.id = "copy-\(index)"
                    records.append(copy)
                }
            }
            let once = LocalTodoAgendaArrange.agenda(records, now: now, timeZone: zone, windowed: false)
            let twice = LocalTodoAgendaArrange.agenda(once, now: now, timeZone: zone, windowed: false)
            #expect(twice == once)
            #expect(agendaIsOrdered(once))
            #expect(agendaHasNoDuplicate(once))
            #expect(once.allSatisfy { item in records.contains { $0.id == item.id } })
        }
    }

    /// The same series instant collapses, and so does the same title, start, end and all-day flag.
    private func agendaHasNoDuplicate(_ records: [LocalAgendaRecord]) -> Bool {
        var seriesStarts: Set<String> = []
        var mirrors: Set<String> = []
        for record in records {
            let series = "\(record.seriesID)|\(Int(record.start.timeIntervalSinceReferenceDate.rounded()))"
            let mirror = "\(record.title.precomposedStringWithCanonicalMapping.lowercased())|\(Int(record.start.timeIntervalSinceReferenceDate.rounded()))|\(Int(record.end.timeIntervalSinceReferenceDate.rounded()))|\(record.isAllDay)"
            if seriesStarts.contains(series) || mirrors.contains(mirror) { return false }
            seriesStarts.insert(series)
            mirrors.insert(mirror)
        }
        return true
    }

    private func agendaIsOrdered(_ records: [LocalAgendaRecord]) -> Bool {
        zip(records, records.dropFirst()).allSatisfy { left, right in
            if left.start != right.start { return left.start < right.start }
            if left.isAllDay != right.isAllDay { return left.isAllDay && !right.isAllDay }
            return left.title.localizedStandardCompare(right.title) != .orderedDescending
        }
    }

    // MARK: No writes

    @Test func readingUsesTheInjectedClockAndDoesNotWrite() async {
        let fixed = Self.instant(2026, 3, 8, 12, 0, zone: "America/New_York")
        let store = SyntheticLocalStore(todos: [todo("Buy milk")], agenda: [])
        let clock = LocalTodoAgendaClock { fixed }
        let snapshot = await LocalTodoAgendaPull.read(
            todos: store, agenda: store, presence: store, clock: clock, timeZone: zone)
        #expect(store.nowSeen == fixed)
        #expect(store.saves == 0)
        #expect(store.removes == 0)
        #expect(snapshot.todos.map(\.title) == ["Buy milk"])
        let effects = LocalTodoAgendaMachine().reduce(.setEnabled(true), now: fixed, timeZone: zone).1
        for effect in effects {
            switch effect {
            case .requestAccess, .read: break
            }
        }
    }

    @Test func theReaderSourceDoesNotSaveRemoveOrLeaveTheMac() throws {
        let root = try repoRoot()
        let paths = [
            "Sources/ZeusCore/LocalTodoAgenda/LocalTodoAgenda.swift",
            "Sources/ZeusCore/LocalTodoAgenda/LocalTodoAgendaMachine.swift",
            "Sources/ZeusCore/LocalTodoAgenda/LocalTodoAgendaStore.swift",
            "Sources/Zeus/LocalTodoAgenda/EventKitLocalSources.swift",
        ]
        let forbidden = [
            "save(", "remove(", "commit(", "NSAppleScript", "osascript", "tell application",
            "URLSession", "MSAL", "Entra", "SecItem", "HTTPCookie", "Group Containers",
            "Library/Containers", "kSec", "microsoft.graph",
        ]
        for relative in paths {
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            for token in forbidden {
                #expect(!text.contains(token), "\(relative) contains \(token)")
            }
        }
        let machine = try repoText("Sources/ZeusCore/LocalTodoAgenda/LocalTodoAgendaMachine.swift")
        #expect(!machine.contains("default:"))
        let reader = try repoText("Sources/Zeus/LocalTodoAgenda/EventKitLocalSources.swift")
        #expect(reader.contains("requestFullAccessToEvents"))
        #expect(reader.contains("requestFullAccessToReminders"))
        #expect(reader.contains("@unknown default"))
        #expect(reader.contains("canImport(EventKit)"))
    }
}

private struct SplitMix64: Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private final class SyntheticLocalStore: TodoSource, AgendaSource, LocalPresenceSource, @unchecked Sendable {
    var todos: [LocalTodoRecord]
    var agenda: [LocalAgendaRecord]
    var nowSeen: Date?
    var saves = 0
    var removes = 0

    init(todos: [LocalTodoRecord], agenda: [LocalAgendaRecord]) {
        self.todos = todos
        self.agenda = agenda
    }

    func save() { saves += 1 }
    func remove() { removes += 1 }

    func loadTodos(now: Date, timeZone: TimeZone) async -> [LocalTodoRecord] {
        nowSeen = now
        return todos
    }

    func loadAgenda(now: Date, timeZone: TimeZone) async -> [LocalAgendaRecord] {
        nowSeen = now
        return agenda
    }

    func presence() async -> LocalAppPresence {
        LocalAppPresence(outlookInstalled: true, toDoInstalled: true, microsoftSources: ["Exchange"])
    }
}

private func repoRoot() throws -> URL {
    if let given = ProcessInfo.processInfo.environment["ZEUS_REPO_ROOT"] {
        return URL(fileURLWithPath: given)
    }
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<8 {
        url.deleteLastPathComponent()
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            return url
        }
    }
    throw RepoRootError.missing
}

private func repoText(_ relative: String) throws -> String {
    try String(contentsOf: repoRoot().appendingPathComponent(relative), encoding: .utf8)
}

private enum RepoRootError: Error { case missing }
