import Foundation
import ZeusCore

/// Tells the other Zeus key monitors about a key the tiling tap consumed.
enum TilingConsumedKey {
    static let notification = Notification.Name("app.zeus.tiling.consumedKey")
    private static let eventKey = "event"
    private static let timeKey = "time"

    /// `time` is when the key went down or up, on the clock `ProcessInfo.systemUptime` reads. The monitors read a key at
    /// that time, not at the time the main queue gets to it.
    nonisolated static func post(_ event: ShortcutEvent, at time: TimeInterval? = nil) {
        var info: [String: Any] = [eventKey: event]
        if let time { info[timeKey] = time }
        NotificationCenter.default.post(name: notification, object: nil, userInfo: info)
    }

    nonisolated static func timestamp(in note: Notification) -> TimeInterval? {
        note.userInfo?[timeKey] as? TimeInterval
    }

    nonisolated static func event(in note: Notification) -> ShortcutEvent? {
        note.userInfo?[eventKey] as? ShortcutEvent
    }
}
