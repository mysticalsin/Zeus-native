import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// E4 session source. L0 has not merged, so this file watches the two workspace session
/// notifications and the two lock names itself. A later lock-screen monitor can replace the body.
/// Sleep, wake and a Space change are not session facts. The presence controller reads `active`
/// and `locked` and applies them. This file does not declare Bluetooth access or device facts.

struct EarbudsSessionNote: Equatable, Sendable {
    var active: Bool
    var locked: Bool
}

protocol EarbudsSessionReading: AnyObject {
    var active: Bool { get }
    var locked: Bool { get }
    func start(_ onChange: @escaping @Sendable (EarbudsSessionNote) -> Void)
    func stop()
}

enum EarbudsSessionBoard: Equatable, Sendable {
    case workspace
    case distributed
}

enum EarbudsSessionBook {
    /// Raw value of `NSWorkspace.sessionDidResignActiveNotification`.
    static let resign = "NSWorkspaceSessionDidResignActiveNotification"
    /// Raw value of `NSWorkspace.sessionDidBecomeActiveNotification`.
    static let become = "NSWorkspaceSessionDidBecomeActiveNotification"
    /// Distributed name observed by the notch for a locked screen.
    static let locked = "com.apple.screenIsLocked"
    /// Distributed name observed by the notch for an unlocked screen.
    static let unlocked = "com.apple.screenIsUnlocked"

    static let watched = [resign, become, locked, unlocked]

    /// A process that just launched is in this session, and no lock notice has arrived.
    static let initial = EarbudsSessionNote(active: true, locked: false)

    static func board(_ name: String) -> EarbudsSessionBoard? {
        switch name {
        case resign, become: .workspace
        case locked, unlocked: .distributed
        default: nil
        }
    }

    /// The next note, or nil when the name is not one of the four or the fact is already held.
    static func apply(_ name: String, to note: EarbudsSessionNote) -> EarbudsSessionNote? {
        var next = note
        switch name {
        case resign: next.active = false
        case become: next.active = true
        case locked: next.locked = true
        case unlocked: next.locked = false
        default: return nil
        }
        return next == note ? nil : next
    }
}

struct EarbudsSessionRegistration: Sendable {
    let remove: @Sendable () -> Void
}

/// Drops one registration. A second drop does nothing.
final class EarbudsSessionObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var remove: (() -> Void)?

    init(_ remove: @escaping () -> Void) {
        self.remove = remove
    }

    func drop() {
        lock.lock()
        let action = remove
        remove = nil
        lock.unlock()
        action?()
    }
}

/// Holds the session note and the four registrations. Tests pass an installer and never post a real notification.
final class LiveEarbudsSessionSource: EarbudsSessionReading, @unchecked Sendable {
    private let lock = NSLock()
    private var note = EarbudsSessionBook.initial
    private var onChange: (@Sendable (EarbudsSessionNote) -> Void)?
    private var held: [EarbudsSessionRegistration] = []
    private var started = false
    private let install: @Sendable (String, @escaping @Sendable () -> Void) -> EarbudsSessionRegistration?

    init(install: @escaping @Sendable (String, @escaping @Sendable () -> Void) -> EarbudsSessionRegistration?) {
        self.install = install
    }

    /// The source that registers the four system names. Tests do not call this.
    static func live() -> LiveEarbudsSessionSource {
        LiveEarbudsSessionSource(install: EarbudsSessionHardware.install)
    }

    var active: Bool { current.active }
    var locked: Bool { current.locked }

    func start(_ handler: @escaping @Sendable (EarbudsSessionNote) -> Void) {
        lock.lock()
        if started {
            lock.unlock()
            return
        }
        started = true
        onChange = handler
        lock.unlock()

        var added: [EarbudsSessionRegistration] = []
        for name in EarbudsSessionBook.watched {
            let registration = install(name) { [weak self] in
                self?.deliver(name)
            }
            if let registration {
                added.append(registration)
            }
        }

        var drop: [EarbudsSessionRegistration] = []
        lock.lock()
        if started {
            held = added
        } else {
            drop = added
        }
        lock.unlock()
        for registration in drop {
            registration.remove()
        }
    }

    func stop() {
        lock.lock()
        let drop = held
        held = []
        started = false
        onChange = nil
        lock.unlock()
        for registration in drop {
            registration.remove()
        }
    }

    func deliver(_ name: String) {
        var handler: (@Sendable (EarbudsSessionNote) -> Void)?
        var next: EarbudsSessionNote?
        lock.lock()
        if started, let updated = EarbudsSessionBook.apply(name, to: note) {
            note = updated
            next = updated
            handler = onChange
        }
        lock.unlock()
        if let next, let handler {
            handler(next)
        }
    }

    private var current: EarbudsSessionNote {
        lock.lock()
        defer { lock.unlock() }
        return note
    }
}

enum EarbudsSessionHardware {
    /// Registers one name. A name outside the four returns nil and adds nothing.
    /// `NSWorkspace` is main-actor isolated, so the registration hops with `assumeIsolated`.
    /// The block itself is built here and runs on the main queue. Tests never call this.
    nonisolated static func install(
        _ name: String,
        _ onChange: @escaping @Sendable () -> Void
    ) -> EarbudsSessionRegistration? {
        #if canImport(AppKit)
        guard let board = EarbudsSessionBook.board(name) else { return nil }
        return MainActor.assumeIsolated {
            let center: NotificationCenter
            switch board {
            case .workspace:
                center = NSWorkspace.shared.notificationCenter
            case .distributed:
                center = DistributedNotificationCenter.default()
            }
            let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
                onChange()
            }
            let box = EarbudsSessionObserver {
                center.removeObserver(token)
            }
            return EarbudsSessionRegistration { box.drop() }
        }
        #else
        _ = name
        _ = onChange
        return nil
        #endif
    }
}
