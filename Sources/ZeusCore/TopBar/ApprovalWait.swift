import Foundation

/// One approval card's wait.
///
/// The timeout used to be an unstructured task that nobody stored. Finishing was idempotent, so a
/// late timeout did not resume the caller twice, but the sleep kept that continuation until the
/// full timeout after the person had answered. The phase is the wait. An answer or the timeout
/// resolves it once, and the controller cancels the sleep it stored for `.armTimeout`.
public enum ApprovalWait {
    public enum Phase: Equatable, Sendable {
        case idle
        case waiting(id: String)
    }

    public enum Event: Equatable, Sendable {
        case begin(id: String)
        case answer(id: String)
        case timeout(id: String)
    }

    public enum Effect: Equatable, Sendable {
        /// Start the timeout sleep and keep that task.
        case armTimeout(id: String)
        /// Resume the waiter once and cancel the stored sleep.
        case resolve(id: String)
    }

    public static func reduce(_ phase: Phase, _ event: Event) -> (Phase, [Effect]) {
        switch (phase, event) {
        case (.idle, .begin(let id)):
            return (.waiting(id: id), [.armTimeout(id: id)])
        case (.waiting(let current), .answer(let id)) where current == id:
            return (.idle, [.resolve(id: id)])
        case (.waiting(let current), .timeout(let id)) where current == id:
            return (.idle, [.resolve(id: id)])
        default:
            return (phase, [])
        }
    }
}
