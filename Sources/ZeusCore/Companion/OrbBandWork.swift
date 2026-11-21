import Foundation

/// Order of work for one playback buffer.
public enum OrbBandWork {
    public enum Step: String, Equatable, Sendable {
        case queuePlayback
        case analyseBands
    }

    /// The band maths still runs before the buffer is queued.
    public static func steps(personaIsOrb: Bool) -> [Step] {
        personaIsOrb ? [.queuePlayback, .analyseBands] : [.queuePlayback]
    }
}

/// Reads the persona once, then again only after defaults change.
public enum OrbPersonaCache {
    private static let lock = NSLock()
    private static var cached: Bool?
    private static var observer: NSObjectProtocol?

    public static func publishes() -> Bool {
        lock.lock()
        if observer == nil {
            lock.unlock()
            let token = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: nil
            ) { _ in
                lock.lock()
                cached = nil
                lock.unlock()
            }
            lock.lock()
            observer = token
            lock.unlock()
        } else {
            lock.unlock()
        }
        lock.lock()
        if let cached {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let next = PersonaCatalog.current().mascotKind == .orb
        lock.lock()
        cached = next
        lock.unlock()
        return next
    }
}
