import Foundation

/// Where a local task and agenda read is. The switch names every phase.
public enum LocalTodoAgendaPhase: Equatable, Sendable {
    case off
    case permissionNeeded
    case denied(LocalAccessPair)
    case loading
    case missingApp(LocalMissingReason)
    case empty
    case populated(LocalTodoAgendaView)
    case error(LocalTodoAgendaFailure)
}

public enum LocalTodoAgendaEvent: Equatable, Sendable {
    case setEnabled(Bool)
    case refresh(LocalAccessPair)
    case permission(LocalAccessPair)
    case loaded(generation: Int, LocalMicrosoftSnapshot)
    case failed(generation: Int, LocalTodoAgendaFailure)
}

/// The only things a read may ask the Mac to do.
public enum LocalTodoAgendaEffect: Equatable, Sendable {
    case requestAccess
    case read(generation: Int)
}

/// One phase at a time. Time arrives as `now`. A load whose generation is not the current one is ignored.
public struct LocalTodoAgendaMachine: Equatable, Sendable {
    public private(set) var phase: LocalTodoAgendaPhase
    public private(set) var enabled: Bool
    public private(set) var generation: Int
    public private(set) var access: LocalAccessPair

    public init() {
        phase = .off
        enabled = false
        generation = 0
        access = LocalAccessPair(events: .notAsked, reminders: .notAsked)
    }

    public func reduce(_ event: LocalTodoAgendaEvent, now: Date, timeZone: TimeZone) -> (LocalTodoAgendaMachine, [LocalTodoAgendaEffect]) {
        var copy = self
        let effects = copy.apply(event, now: now, timeZone: timeZone)
        return (copy, effects)
    }

    private mutating func apply(_ event: LocalTodoAgendaEvent, now: Date, timeZone: TimeZone) -> [LocalTodoAgendaEffect] {
        switch event {
        case .setEnabled(false):
            enabled = false
            if phase == .loading { generation += 1 }
            phase = .off
            return []
        case .setEnabled(true):
            enabled = true
            return follow()
        case .refresh(let pair):
            access = pair
            guard enabled else { return [] }
            return follow()
        case .permission(let pair):
            access = pair
            guard enabled else { return [] }
            return follow()
        case .loaded(let generation, let snapshot):
            guard enabled, phase == .loading, generation == self.generation else { return [] }
            phase = LocalTodoAgendaArrange.phase(for: snapshot, now: now, timeZone: timeZone)
            return []
        case .failed(let generation, let failure):
            guard enabled, phase == .loading, generation == self.generation else { return [] }
            phase = .error(failure)
            return []
        }
    }

    /// Read when either side can be read. Ask when a side is still unanswered and nothing can be read. Otherwise the answer is a denial.
    private mutating func follow() -> [LocalTodoAgendaEffect] {
        switch gate(access) {
        case .read:
            generation += 1
            phase = .loading
            return [.read(generation: generation)]
        case .request:
            phase = .permissionNeeded
            return [.requestAccess]
        case .denied:
            phase = .denied(access)
            return []
        }
    }

    private enum Gate: Equatable {
        case read, request, denied
    }

    private func gate(_ access: LocalAccessPair) -> Gate {
        if access.events == .allowed || access.reminders == .allowed { return .read }
        if access.events == .notAsked || access.reminders == .notAsked { return .request }
        return .denied
    }
}
