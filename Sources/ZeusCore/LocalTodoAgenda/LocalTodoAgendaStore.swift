import Foundation

/// Open tasks from one local source. The method list is the whole contract: there is no place to store a change.
public protocol TodoSource: Sendable {
    func loadTodos(now: Date, timeZone: TimeZone) async -> [LocalTodoRecord]
}

/// Events from one local source, for the caller to window. No method here changes an event.
public protocol AgendaSource: Sendable {
    func loadAgenda(now: Date, timeZone: TimeZone) async -> [LocalAgendaRecord]
}

/// Whether the Microsoft apps are on this Mac, and which Exchange or Outlook sources the Mac already lists.
public protocol LocalPresenceSource: Sendable {
    func presence() async -> LocalAppPresence
}

/// The clock a read uses. Tests pass a fixed instant. The Mac passes its own clock at the edge.
public struct LocalTodoAgendaClock: Sendable {
    public var now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date) {
        self.now = now
    }
}

/// Asks the three sources once, all at the clock's instant.
public enum LocalTodoAgendaPull {
    public static func read(
        todos: any TodoSource,
        agenda: any AgendaSource,
        presence: any LocalPresenceSource,
        clock: LocalTodoAgendaClock,
        timeZone: TimeZone
    ) async -> LocalMicrosoftSnapshot {
        let now = clock.now()
        let todoRecords = await todos.loadTodos(now: now, timeZone: timeZone)
        let agendaRecords = await agenda.loadAgenda(now: now, timeZone: timeZone)
        let presenceValue = await presence.presence()
        return LocalMicrosoftSnapshot(todos: todoRecords, agenda: agendaRecords, presence: presenceValue)
    }
}
