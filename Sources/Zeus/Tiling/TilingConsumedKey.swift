import Foundation
import ZeusCore

/// Tells the other Zeus key monitors about a key the tiling tap consumed.
enum TilingConsumedKey {
    static let notification = Notification.Name("app.zeus.tiling.consumedKey")
    private static let eventKey = "event"

    nonisolated static func post(_ event: ShortcutEvent) {
        NotificationCenter.default.post(name: notification, object: nil, userInfo: [eventKey: event])
    }

    nonisolated static func event(in note: Notification) -> ShortcutEvent? {
        note.userInfo?[eventKey] as? ShortcutEvent
    }
}
