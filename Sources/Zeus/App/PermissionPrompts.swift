import Foundation
import ZeusCore

/// Runs each consent request through `RequestFlight`: the first asker raises the prompt, anyone who asks
/// for the same key while it is up waits for that answer instead of raising a second prompt.
@MainActor
final class PermissionPrompts {
    static let shared = PermissionPrompts()

    private var flights = RequestFlights<String>()
    private var tasks: [String: Task<Void, Never>] = [:]

    func isAsking(_ key: String) -> Bool { flights.isAsking(key) }

    /// Runs `ask` unless `key` is already asking; either way returns once the live request has finished.
    /// True when this call raised the prompt.
    @discardableResult
    func run(_ key: String, ask: @escaping @MainActor () async -> Void) async -> Bool {
        switch flights.request(key) {
        case .begin(let token):
            let task = Task { @MainActor [weak self] in
                await ask()
                self?.finish(key, token: token)
            }
            tasks[key] = task
            await task.value
            return true
        case .join:
            await tasks[key]?.value
            return false
        }
    }

    private func finish(_ key: String, token: UInt64) {
        if flights.finish(key, token: token) { tasks[key] = nil }
    }
}
