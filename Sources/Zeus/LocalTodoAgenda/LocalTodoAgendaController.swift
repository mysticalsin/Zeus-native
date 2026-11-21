import Foundation
import Observation
import ZeusCore

#if canImport(EventKit)
import EventKit
#endif

/// Agenda data is never sent to an LLM or the network unless the user explicitly asks.
/// The store is created only after the switch is on. Switching off cancels the in-flight read and drops the reader and the EKEventStore.
/// Nothing in this type writes an event or a reminder.
@MainActor @Observable
final class LocalTodoAgendaController {
    static let shared = LocalTodoAgendaController()

    private(set) var phase: LocalTodoAgendaPhase = .off
    @ObservationIgnored private var session = LocalTodoAgendaSession()
    @ObservationIgnored private var task: Task<Void, Never>?
    #if canImport(EventKit)
    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private var reader: EventKitTodoAgendaReader?
    #endif

    private init() {}

    /// Reads the catalog switch. A snapshot never starts a prompt.
    func syncFromSettings() {
        guard !TopBarStyle.isSnapshot else { return }
        let on = FeatureSettings.bool(LocalTodoAgendaSetting.id, default: LocalTodoAgendaSetting.defaultEnabled)
        guard on != session.machine.enabled else { return }
        apply(.setEnabled(on))
    }

    private func apply(_ event: LocalTodoAgendaEvent) {
        let (next, effects) = session.reduce(event, now: Date(), timeZone: .current)
        session = next
        phase = next.machine.phase
        for effect in effects {
            switch effect {
            case .dropReader:
                dropReader()
            case .requestAccess:
                startRequest()
            case .read(let generation):
                startRead(generation)
            }
        }
    }

    /// Cancels any in-flight read and releases the reader and the store.
    private func dropReader() {
        task?.cancel()
        task = nil
        #if canImport(EventKit)
        reader = nil
        store = nil
        #endif
    }

    private func startRequest() {
        #if canImport(EventKit)
        guard !TopBarStyle.isSnapshot else { return }
        let created = makeStore()
        store = created
        let source = EventKitTodoAgendaReader(store: created)
        reader = source
        task?.cancel()
        task = Task { @MainActor in
            let pair = await source.requestAccess()
            guard !Task.isCancelled else { return }
            self.apply(.permission(pair))
        }
        #endif
    }

    private func startRead(_ generation: Int) {
        #if canImport(EventKit)
        guard !TopBarStyle.isSnapshot else { return }
        let created = store ?? makeStore()
        store = created
        let source = reader ?? EventKitTodoAgendaReader(store: created)
        reader = source
        task?.cancel()
        let clock = LocalTodoAgendaClock { Date() }
        let zone = TimeZone.current
        task = Task { @MainActor in
            let snapshot = await LocalTodoAgendaPull.read(
                todos: source, agenda: source, presence: source, clock: clock, timeZone: zone)
            guard !Task.isCancelled else { return }
            guard self.session.machine.enabled, self.session.machine.generation == generation else { return }
            self.apply(.loaded(generation: generation, snapshot))
        }
        #endif
    }

    #if canImport(EventKit)
    private func makeStore() -> EKEventStore {
        EKEventStore()
    }
    #endif
}
