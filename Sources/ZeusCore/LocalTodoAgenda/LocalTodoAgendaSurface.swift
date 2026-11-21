import Foundation

/// Agenda data is never sent to an LLM or the network unless the user explicitly asks.
public enum LocalTodoAgendaPrivacy {
    public static let staysLocal = "Agenda data is never sent to an LLM or the network unless the user explicitly asks."
}

/// A settings file may turn this switch off. It cannot turn it on.
public enum LocalTodoAgendaImport {
    public static func blocksEnable(id: String, value: String) -> Bool {
        id == LocalTodoAgendaSetting.id && value == "true"
    }

    /// The value an import is allowed to leave behind. `true` is refused, so the stored value stays.
    public static func accepted(current: String, imported: String) -> String {
        blocksEnable(id: LocalTodoAgendaSetting.id, value: imported) ? current : imported
    }
}

/// One of Zeus's own to-dos, shown while the Microsoft read is off. Not a calendar record.
public struct LocalTodoAgendaOwnItem: Equatable, Sendable {
    public var title: String
    public var meta: String

    public init(title: String, meta: String) {
        self.title = title
        self.meta = meta
    }
}

public struct LocalTodoAgendaRowModel: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var meta: String
    /// Overdue is the word in `meta`. The row is marked so type can underline it. Colour is not the status.
    public var emphasized: Bool

    public init(id: String, title: String, meta: String, emphasized: Bool) {
        self.id = id
        self.title = title
        self.meta = meta
        self.emphasized = emphasized
    }
}

public struct LocalTodoAgendaGroupModel: Equatable, Sendable, Identifiable {
    /// Empty for the dated list. "No date" for tasks with no due day.
    public var name: String
    public var rows: [LocalTodoAgendaRowModel]

    public var id: String { name }

    public init(name: String, rows: [LocalTodoAgendaRowModel]) {
        self.name = name
        self.rows = rows
    }
}

public struct LocalTodoAgendaColumnModel: Equatable, Sendable {
    public var kicker: String
    public var head: String
    public var body: String?
    public var note: String?
    public var warns: Bool
    public var loading: Bool
    public var groups: [LocalTodoAgendaGroupModel]
    /// Text only. The page has no control that grants Calendar or Reminders access.
    public var grantsAccess: Bool

    public init(kicker: String, head: String, body: String? = nil, note: String? = nil, warns: Bool = false, loading: Bool = false, groups: [LocalTodoAgendaGroupModel] = [], grantsAccess: Bool = false) {
        self.kicker = kicker
        self.head = head
        self.body = body
        self.note = note
        self.warns = warns
        self.loading = loading
        self.groups = groups
        self.grantsAccess = grantsAccess
    }
}

/// What the existing To-do page says. A state change replaces this value immediately.
public struct LocalTodoAgendaSurface: Equatable, Sendable {
    public var voiceOverLabel: String
    public var left: LocalTodoAgendaColumnModel
    public var right: LocalTodoAgendaColumnModel
    /// The loading bar is the only motion, and only while Reduce Motion is off.
    public var loadingBarMoves: Bool
    /// Off keeps Zeus's own list. Every other phase draws the read in its place.
    public var showsOwnList: Bool
    public var replacesImmediately: Bool

    public init(voiceOverLabel: String, left: LocalTodoAgendaColumnModel, right: LocalTodoAgendaColumnModel, loadingBarMoves: Bool, showsOwnList: Bool, replacesImmediately: Bool) {
        self.voiceOverLabel = voiceOverLabel
        self.left = left
        self.right = right
        self.loadingBarMoves = loadingBarMoves
        self.showsOwnList = showsOwnList
        self.replacesImmediately = replacesImmediately
    }
}

public enum LocalTodoAgendaSurfaceMap {
    public static func make(phase: LocalTodoAgendaPhase, ownItems: [LocalTodoAgendaOwnItem], reduceMotion: Bool) -> LocalTodoAgendaSurface {
        let pair = columns(phase, ownItems: ownItems)
        let loading = pair.left.loading || pair.right.loading
        return LocalTodoAgendaSurface(
            voiceOverLabel: "\(name(phase)), To-do and Agenda",
            left: pair.left,
            right: pair.right,
            loadingBarMoves: loading && !reduceMotion,
            showsOwnList: phase == .off,
            replacesImmediately: true)
    }

    private static func name(_ phase: LocalTodoAgendaPhase) -> String {
        switch phase {
        case .off: "off"
        case .permissionNeeded: "permission needed"
        case .denied: "denied"
        case .loading: "loading"
        case .missingApp(.applicationsNotInstalled): "app missing (a)"
        case .missingApp(.notInMacAccounts): "app missing (b)"
        case .empty: "empty"
        case .populated: "populated"
        case .error: "error"
        }
    }

    private static func columns(_ phase: LocalTodoAgendaPhase, ownItems: [LocalTodoAgendaOwnItem]) -> (left: LocalTodoAgendaColumnModel, right: LocalTodoAgendaColumnModel) {
        switch phase {
        case .off:
            return (
                LocalTodoAgendaColumnModel(
                    kicker: "To-do",
                    head: "Kept on this Mac",
                    note: "Microsoft tasks stay off.",
                    groups: ownItems.isEmpty ? [] : [LocalTodoAgendaGroupModel(name: "", rows: ownItems.enumerated().map { index, item in
                        LocalTodoAgendaRowModel(id: "own-\(index)", title: item.title, meta: item.meta, emphasized: false)
                    })]),
                LocalTodoAgendaColumnModel(
                    kicker: "Agenda",
                    head: "Not reading Outlook",
                    body: "Turn on Tasks and agenda from this Mac. Zeus does not sign in."))
        case .permissionNeeded:
            return (
                LocalTodoAgendaColumnModel(
                    kicker: "To-do",
                    head: "macOS will ask",
                    body: "Calendars and Reminders, read only. The system sheet is the ask. This page has no control that grants it."),
                LocalTodoAgendaColumnModel(
                    kicker: "Agenda",
                    head: "Same prompt",
                    body: "Outlook is read from the calendars already on this Mac."))
        case .denied:
            return (
                LocalTodoAgendaColumnModel(
                    kicker: "To-do",
                    head: "Reminders stays closed",
                    body: "Zeus will not ask again from here. System Settings, Privacy & Security, can allow it.",
                    warns: true),
                LocalTodoAgendaColumnModel(
                    kicker: "Agenda",
                    head: "Calendars stays closed",
                    body: "The lists already in Zeus are unchanged.",
                    warns: true))
        case .loading:
            return (
                LocalTodoAgendaColumnModel(
                    kicker: "To-do",
                    head: "Loading",
                    body: "Reading reminders the Mac already has.",
                    loading: true),
                LocalTodoAgendaColumnModel(
                    kicker: "Agenda",
                    head: "Loading",
                    body: "Reading today's events.",
                    loading: true))
        case .missingApp(.applicationsNotInstalled):
            return (
                LocalTodoAgendaColumnModel(
                    kicker: "Not installed",
                    head: "Nothing to read",
                    body: "Outlook and To Do are not on this Mac, and Calendar has no Exchange account."),
                LocalTodoAgendaColumnModel(
                    kicker: "Agenda",
                    head: "Nothing to read",
                    body: "No Exchange or Outlook calendar source on this Mac."))
        case .missingApp(.notInMacAccounts):
            return (
                LocalTodoAgendaColumnModel(
                    kicker: "Not in the Mac's calendars",
                    head: "Add the account on the Mac",
                    body: "Outlook is on this Mac. Its calendar is not in the Mac's calendars. System Settings, Internet Accounts. Zeus does not sign in."),
                LocalTodoAgendaColumnModel(
                    kicker: "Agenda",
                    head: "Not in the Mac's calendars",
                    body: "Zeus does not reach into Outlook."))
        case .empty:
            return (
                LocalTodoAgendaColumnModel(
                    kicker: "To-do",
                    head: "Nothing due",
                    body: "No open Microsoft tasks."),
                LocalTodoAgendaColumnModel(
                    kicker: "Agenda",
                    head: "Nothing today",
                    body: "The Exchange calendar has no event on this day."))
        case .populated(let view):
            return (
                LocalTodoAgendaColumnModel(
                    kicker: "To-do",
                    head: "From Reminders",
                    groups: taskGroups(view.todos)),
                LocalTodoAgendaColumnModel(
                    kicker: "Agenda",
                    head: "From the Mac's calendars",
                    groups: eventGroups(view.agenda)))
        case .error:
            return (
                LocalTodoAgendaColumnModel(
                    kicker: "To-do",
                    head: "Could not read",
                    body: "The reminders on this Mac could not be read. Nothing was changed.",
                    warns: true),
                LocalTodoAgendaColumnModel(
                    kicker: "Agenda",
                    head: "Could not read",
                    body: "Try again from the setting. Zeus does not sign in to try another way.",
                    warns: true))
        }
    }

    private static func taskGroups(_ lines: [LocalTodoLine]) -> [LocalTodoAgendaGroupModel] {
        let dated = lines.filter { $0.dueLabel != "No date" }
        let undated = lines.filter { $0.dueLabel == "No date" }
        var groups: [LocalTodoAgendaGroupModel] = []
        if !dated.isEmpty {
            groups.append(LocalTodoAgendaGroupModel(name: "", rows: dated.map { row($0, emphasized: $0.dueLabel == "Overdue") }))
        }
        if !undated.isEmpty {
            groups.append(LocalTodoAgendaGroupModel(name: "No date", rows: undated.map { row($0, emphasized: false) }))
        }
        return groups
    }

    private static func eventGroups(_ lines: [LocalAgendaLine]) -> [LocalTodoAgendaGroupModel] {
        guard !lines.isEmpty else { return [] }
        return [LocalTodoAgendaGroupModel(name: "", rows: lines.map { line in
            LocalTodoAgendaRowModel(id: line.id, title: line.title, meta: line.when, emphasized: false)
        })]
    }

    private static func row(_ line: LocalTodoLine, emphasized: Bool) -> LocalTodoAgendaRowModel {
        LocalTodoAgendaRowModel(id: line.id, title: line.title, meta: line.dueLabel, emphasized: emphasized)
    }
}

/// Holds the phase machine and whether a reader is alive. Switching off always drops it.
public enum LocalTodoAgendaSessionEffect: Equatable, Sendable {
    case requestAccess
    case read(generation: Int)
    case dropReader
}

public struct LocalTodoAgendaSession: Equatable, Sendable {
    public private(set) var machine: LocalTodoAgendaMachine
    public private(set) var holdsReader: Bool

    public init() {
        machine = LocalTodoAgendaMachine()
        holdsReader = false
    }

    public func reduce(_ event: LocalTodoAgendaEvent, now: Date, timeZone: TimeZone) -> (LocalTodoAgendaSession, [LocalTodoAgendaSessionEffect]) {
        var copy = self
        let effects = copy.apply(event, now: now, timeZone: timeZone)
        return (copy, effects)
    }

    private mutating func apply(_ event: LocalTodoAgendaEvent, now: Date, timeZone: TimeZone) -> [LocalTodoAgendaSessionEffect] {
        let wasEnabled = machine.enabled
        let (next, machineEffects) = machine.reduce(event, now: now, timeZone: timeZone)
        machine = next
        var effects = machineEffects.map(Self.lift)
        if effects.contains(where: isWork) {
            holdsReader = true
        }
        if wasEnabled && !machine.enabled {
            holdsReader = false
            effects.append(.dropReader)
        }
        return effects
    }

    private static func lift(_ effect: LocalTodoAgendaEffect) -> LocalTodoAgendaSessionEffect {
        switch effect {
        case .requestAccess: .requestAccess
        case .read(let generation): .read(generation: generation)
        }
    }

    private func isWork(_ effect: LocalTodoAgendaSessionEffect) -> Bool {
        switch effect {
        case .requestAccess, .read: true
        case .dropReader: false
        }
    }
}

/// Fixed sentences. A calendar title, a source title, or a task title is not a parameter.
public enum LocalTodoAgendaLog {
    public enum Kind: Equatable, Sendable {
        case switchedOn
        case switchedOff
        case readStarted
        case readFinished
        case readFailed
        case accessAsked
        case readerDropped
    }

    public static func line(_ kind: Kind) -> String {
        switch kind {
        case .switchedOn: "local agenda switch on"
        case .switchedOff: "local agenda switch off"
        case .readStarted: "local agenda read started"
        case .readFinished: "local agenda read finished"
        case .readFailed: "local agenda read failed"
        case .accessAsked: "local agenda access asked"
        case .readerDropped: "local agenda reader dropped"
        }
    }
}
