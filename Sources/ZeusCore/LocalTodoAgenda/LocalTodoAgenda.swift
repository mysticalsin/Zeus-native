import Foundation

/// The switch that keeps a Microsoft task and agenda read off until someone turns it on.
/// The settings catalog stores the same id. The row stays hidden until the top bar is approved.
public enum LocalTodoAgendaSetting {
    public static let id = "todo.microsoftLocal"
    public static let defaultEnabled = false
}

/// What macOS has said about Calendar or Reminders. Write-only is not a read.
public enum LocalAccessStatus: Equatable, Sendable {
    case notAsked, allowed, denied, restricted

    /// Restricted wins, then a full read, then write-only or a denial. Anything else has not been asked.
    public static func map(fullAccess: Bool, writeOnly: Bool, denied: Bool, restricted: Bool) -> LocalAccessStatus {
        if restricted { return .restricted }
        if fullAccess { return .allowed }
        if writeOnly || denied { return .denied }
        return .notAsked
    }
}

public struct LocalAccessPair: Equatable, Sendable {
    public var events: LocalAccessStatus
    public var reminders: LocalAccessStatus

    public init(events: LocalAccessStatus, reminders: LocalAccessStatus) {
        self.events = events
        self.reminders = reminders
    }
}

/// A task the Mac already has. Synthetic in tests. Never a task read from a person's list during a test.
public struct LocalTodoRecord: Equatable, Sendable {
    public var id: String
    public var title: String
    public var listName: String
    public var sourceName: String
    public var sourceKind: String
    public var due: Date?
    public var isAllDay: Bool
    public var timeZoneIdentifier: String
    public var completed: Bool

    public init(id: String, title: String, listName: String, sourceName: String, sourceKind: String, due: Date?, isAllDay: Bool, timeZoneIdentifier: String, completed: Bool) {
        self.id = id
        self.title = title
        self.listName = listName
        self.sourceName = sourceName
        self.sourceKind = sourceKind
        self.due = due
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.completed = completed
    }
}

/// One occurrence of an event the Mac already has.
public struct LocalAgendaRecord: Equatable, Sendable {
    public var id: String
    public var seriesID: String
    public var title: String
    public var calendarName: String
    public var sourceName: String
    public var sourceKind: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var timeZoneIdentifier: String
    public var isRecurring: Bool

    public init(id: String, seriesID: String, title: String, calendarName: String, sourceName: String, sourceKind: String, start: Date, end: Date, isAllDay: Bool, timeZoneIdentifier: String, isRecurring: Bool) {
        self.id = id
        self.seriesID = seriesID
        self.title = title
        self.calendarName = calendarName
        self.sourceName = sourceName
        self.sourceKind = sourceKind
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.isRecurring = isRecurring
    }
}

public struct LocalAppPresence: Equatable, Sendable {
    public var outlookInstalled: Bool
    public var toDoInstalled: Bool
    public var microsoftSources: [String]

    public init(outlookInstalled: Bool, toDoInstalled: Bool, microsoftSources: [String]) {
        self.outlookInstalled = outlookInstalled
        self.toDoInstalled = toDoInstalled
        self.microsoftSources = microsoftSources
    }
}

public struct LocalMicrosoftSnapshot: Equatable, Sendable {
    public var todos: [LocalTodoRecord]
    public var agenda: [LocalAgendaRecord]
    public var presence: LocalAppPresence

    public init(todos: [LocalTodoRecord], agenda: [LocalAgendaRecord], presence: LocalAppPresence) {
        self.todos = todos
        self.agenda = agenda
        self.presence = presence
    }
}

public struct LocalTodoLine: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var listName: String
    public var dueLabel: String

    public init(id: String, title: String, listName: String, dueLabel: String) {
        self.id = id
        self.title = title
        self.listName = listName
        self.dueLabel = dueLabel
    }
}

public struct LocalAgendaLine: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var calendarName: String
    public var when: String
    public var start: Date

    public init(id: String, title: String, calendarName: String, when: String, start: Date) {
        self.id = id
        self.title = title
        self.calendarName = calendarName
        self.when = when
        self.start = start
    }
}

public struct LocalTodoAgendaView: Equatable, Sendable {
    public var todos: [LocalTodoLine]
    public var agenda: [LocalAgendaLine]

    public init(todos: [LocalTodoLine], agenda: [LocalAgendaLine]) {
        self.todos = todos
        self.agenda = agenda
    }
}

public enum LocalMissingReason: Equatable, Sendable {
    /// Neither Microsoft app is on this Mac, and Calendar has no Exchange or Outlook account.
    case applicationsNotInstalled
    /// An app may be installed, but its tasks and events are not in the Mac's accounts.
    case notInMacAccounts
}

public enum LocalTodoAgendaFailure: Equatable, Sendable {
    case readFailed
}

/// Exchange, or a source whose name is Outlook or Exchange. The name rule follows the local calendar reader.
public enum MicrosoftAccountMatch {
    public static func isMicrosoft(sourceName: String, sourceKind: String) -> Bool {
        if sourceKind.caseInsensitiveCompare("exchange") == .orderedSame { return true }
        let name = sourceName.lowercased()
        return name == "outlook" || name == "exchange" || name.hasPrefix("outlook ") || name.hasPrefix("exchange ")
    }
}

/// Dedupe, sort and the day's window. The clock and the time zone are arguments, never `Date()`.
public enum LocalTodoAgendaArrange {
    public static func phase(for snapshot: LocalMicrosoftSnapshot, now: Date, timeZone: TimeZone) -> LocalTodoAgendaPhase {
        let todos = snapshot.todos.filter { record in
            !record.completed && MicrosoftAccountMatch.isMicrosoft(sourceName: record.sourceName, sourceKind: record.sourceKind)
        }
        let agenda = snapshot.agenda.filter { record in
            MicrosoftAccountMatch.isMicrosoft(sourceName: record.sourceName, sourceKind: record.sourceKind)
        }
        let listed = snapshot.presence.microsoftSources.contains { name in
            MicrosoftAccountMatch.isMicrosoft(sourceName: name, sourceKind: "")
        }
        guard listed || !todos.isEmpty || !agenda.isEmpty else {
            if !snapshot.presence.outlookInstalled && !snapshot.presence.toDoInstalled {
                return .missingApp(.applicationsNotInstalled)
            }
            return .missingApp(.notInMacAccounts)
        }
        let todoLines = self.todos(todos, now: now, timeZone: timeZone)
        let agendaLines = self.agenda(agenda, now: now, timeZone: timeZone, windowed: true).map { line(for: $0, viewZone: timeZone) }
        if todoLines.isEmpty && agendaLines.isEmpty { return .empty }
        return .populated(LocalTodoAgendaView(todos: todoLines, agenda: agendaLines))
    }

    public static func agenda(_ records: [LocalAgendaRecord], now: Date, timeZone: TimeZone, windowed: Bool) -> [LocalAgendaRecord] {
        let window = dayWindow(now, timeZone: timeZone)
        let chosen = windowed ? records.filter { overlaps($0, window) } : records
        return dedupe(chosen).sorted(by: agendaOrder)
    }

    public static func todos(_ records: [LocalTodoRecord], now: Date, timeZone: TimeZone) -> [LocalTodoLine] {
        let open = records.filter { !$0.completed }
        return dedupe(open).sorted { todoOrder($0, $1, now: now, timeZone: timeZone) }.map { line(for: $0, now: now, timeZone: timeZone) }
    }

    private static func dedupe(_ records: [LocalTodoRecord]) -> [LocalTodoRecord] {
        var kept: [LocalTodoRecord] = []
        for record in records {
            let key = todoKey(record)
            if kept.contains(where: { todoKey($0) == key }) { continue }
            kept.append(record)
        }
        return kept
    }

    private static func dedupe(_ records: [LocalAgendaRecord]) -> [LocalAgendaRecord] {
        guard !records.isEmpty else { return [] }
        var parent = Array(records.indices)
        func find(_ start: Int) -> Int {
            var index = start
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }
        for left in records.indices {
            for right in (left + 1)..<records.count where sameSeriesInstant(records[left], records[right]) || sameMirror(records[left], records[right]) {
                parent[find(right)] = find(left)
            }
        }
        var grouped: [Int: [LocalAgendaRecord]] = [:]
        var order: [Int] = []
        for index in records.indices {
            let root = find(index)
            if grouped[root] == nil { order.append(root) }
            grouped[root, default: []].append(records[index])
        }
        return order.compactMap { root in
            grouped[root].map { group in group.reduce(group[0], prefer) }
        }
    }

    private static func todoKey(_ record: LocalTodoRecord) -> String {
        let title = record.title.precomposedStringWithCanonicalMapping.lowercased()
        let list = record.listName.lowercased()
        let due = record.due.map { String(stamp($0, zone: zone(record.timeZoneIdentifier))) } ?? ""
        return "\(title)|\(list)|\(due)"
    }

    private static func sameSeriesInstant(_ left: LocalAgendaRecord, _ right: LocalAgendaRecord) -> Bool {
        left.seriesID == right.seriesID && instant(left.start) == instant(right.start)
    }

    private static func sameMirror(_ left: LocalAgendaRecord, _ right: LocalAgendaRecord) -> Bool {
        left.title.precomposedStringWithCanonicalMapping.lowercased() == right.title.precomposedStringWithCanonicalMapping.lowercased()
            && instant(left.start) == instant(right.start)
            && instant(left.end) == instant(right.end)
            && left.isAllDay == right.isAllDay
    }

    private static func prefer(_ current: LocalAgendaRecord, _ candidate: LocalAgendaRecord) -> LocalAgendaRecord {
        let candidateExchange = candidate.sourceKind.caseInsensitiveCompare("exchange") == .orderedSame
        let currentExchange = current.sourceKind.caseInsensitiveCompare("exchange") == .orderedSame
        if candidateExchange && !currentExchange { return candidate }
        return current
    }

    private static func agendaOrder(_ left: LocalAgendaRecord, _ right: LocalAgendaRecord) -> Bool {
        if left.start != right.start { return left.start < right.start }
        if left.isAllDay != right.isAllDay { return left.isAllDay && !right.isAllDay }
        return left.title.localizedStandardCompare(right.title) == .orderedAscending
    }

    private static func todoOrder(_ left: LocalTodoRecord, _ right: LocalTodoRecord, now: Date, timeZone: TimeZone) -> Bool {
        let leftBucket = bucket(left, now: now, timeZone: timeZone)
        let rightBucket = bucket(right, now: now, timeZone: timeZone)
        if leftBucket != rightBucket { return leftBucket < rightBucket }
        if let leftDue = left.due, let rightDue = right.due, leftDue != rightDue { return leftDue < rightDue }
        return left.title.localizedStandardCompare(right.title) == .orderedAscending
    }

    private static func bucket(_ record: LocalTodoRecord, now: Date, timeZone: TimeZone) -> Int {
        guard let due = record.due else { return 3 }
        let dueDay = stamp(due, zone: timeZone)
        let today = stamp(now, zone: timeZone)
        if dueDay < today { return 0 }
        if dueDay == today { return 1 }
        return 2
    }

    private static func line(for record: LocalTodoRecord, now: Date, timeZone: TimeZone) -> LocalTodoLine {
        LocalTodoLine(id: record.id, title: record.title, listName: record.listName, dueLabel: dueLabel(record, now: now, timeZone: timeZone))
    }

    private static func dueLabel(_ record: LocalTodoRecord, now: Date, timeZone: TimeZone) -> String {
        guard let due = record.due else { return "No date" }
        let dueDay = stamp(due, zone: timeZone)
        let today = stamp(now, zone: timeZone)
        if dueDay < today { return "Overdue" }
        if dueDay == today {
            return record.isAllDay ? "Today" : "Today \(clock(due, zone: timeZone))"
        }
        let day = dayText(due, zone: timeZone)
        return record.isAllDay ? day : "\(day) \(clock(due, zone: timeZone))"
    }

    private static func line(for record: LocalAgendaRecord, viewZone: TimeZone) -> LocalAgendaLine {
        let eventZone = zone(record.timeZoneIdentifier)
        let when: String
        if record.isAllDay {
            let span = daySpan(record)
            when = span > 1 ? "All day · \(span) days" : "All day"
        } else {
            let range = "\(clock(record.start, zone: eventZone))–\(clock(record.end, zone: eventZone))"
            if eventZone.identifier == viewZone.identifier {
                when = range
            } else {
                let city = eventZone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? eventZone.identifier
                when = "\(range) · \(city)"
            }
        }
        return LocalAgendaLine(id: record.id, title: record.title, calendarName: record.calendarName, when: when, start: record.start)
    }

    private static func daySpan(_ record: LocalAgendaRecord) -> Int {
        let calendar = gregorian(zone(record.timeZoneIdentifier))
        let start = calendar.startOfDay(for: record.start)
        let end = calendar.startOfDay(for: record.end)
        return max(calendar.dateComponents([.day], from: start, to: end).day ?? 1, 1)
    }

    private static func overlaps(_ record: LocalAgendaRecord, _ window: DateInterval) -> Bool {
        record.start < window.end && record.end > window.start
    }

    private static func dayWindow(_ now: Date, timeZone: TimeZone) -> DateInterval {
        let calendar = gregorian(timeZone)
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    private static func stamp(_ date: Date, zone: TimeZone) -> Int {
        let calendar = gregorian(zone)
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    private static func clock(_ date: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func dayText(_ date: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private static func zone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 0)!
    }

    private static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func instant(_ date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate.rounded())
    }
}
