import Foundation
#if canImport(CoreAudio)
import CoreAudio
#endif

#if !canImport(CoreAudio)
typealias AudioObjectID = UInt32
#endif

/// The one read of `kAudioHardwarePropertyDefaultOutputDevice`.
/// The readers in Fast Actions, Output Devices and the volume listener stay as they are
/// until those files can call this.
enum DefaultOutput {
    nonisolated static func current() -> AudioObjectID? {
        #if canImport(CoreAudio)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
        #else
        return nil
        #endif
    }
}

/// Removes one installed listener. Safe to call more than once.
final class DefaultOutputHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var remove: (() -> Void)?

    init(_ remove: @escaping () -> Void) {
        self.remove = remove
    }

    func removeListener() {
        lock.lock()
        let action = remove
        remove = nil
        lock.unlock()
        action?()
    }
}

/// Subscriber book. One installer call for the first subscriber, one removal with the last.
final class DefaultOutputBook: @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [UUID: @Sendable () -> Void] = [:]
    private var handle: DefaultOutputHandle?
    private var installing = false

    func subscribe(
        _ handler: @escaping @Sendable () -> Void,
        install: @escaping @Sendable (@escaping @Sendable () -> Void) -> DefaultOutputHandle
    ) -> UUID {
        let id = UUID()
        var shouldInstall = false
        lock.lock()
        handlers[id] = handler
        if handle == nil, !installing {
            installing = true
            shouldInstall = true
        }
        lock.unlock()
        if shouldInstall {
            let installed = install { [weak self] in self?.deliver() }
            var drop: DefaultOutputHandle?
            lock.lock()
            installing = false
            if handlers.isEmpty {
                drop = installed
            } else {
                handle = installed
            }
            lock.unlock()
            drop?.removeListener()
        }
        return id
    }

    func unsubscribe(_ id: UUID) {
        var drop: DefaultOutputHandle?
        lock.lock()
        handlers.removeValue(forKey: id)
        if handlers.isEmpty, let installed = handle {
            handle = nil
            drop = installed
        }
        lock.unlock()
        drop?.removeListener()
    }

    /// One change calls each current subscriber once, on the thread that reported it.
    /// The hardware installer hops to the main queue before it reports.
    func deliver() {
        lock.lock()
        let current = Array(handlers.values)
        lock.unlock()
        for handler in current {
            handler()
        }
    }
}

enum DefaultOutputHardware {
    /// Installs one listener on the system object for the default output device.
    /// The block is built in this nonisolated function, then hops to the main thread.
    nonisolated static func install(_ onChange: @escaping @Sendable () -> Void) -> DefaultOutputHandle {
        #if canImport(CoreAudio)
        let registration = CoreAudioRegistration()
        let added = registration.install(onChange)
        return DefaultOutputHandle {
            if added { registration.remove() }
        }
        #else
        _ = onChange
        return DefaultOutputHandle {}
        #endif
    }
}

#if canImport(CoreAudio)
private final class CoreAudioRegistration: @unchecked Sendable {
    let queue = DispatchQueue(label: "app.zeus.output.watch")
    let system = AudioObjectID(kAudioObjectSystemObject)
    var block: AudioObjectPropertyListenerBlock?

    nonisolated func install(_ onChange: @escaping @Sendable () -> Void) -> Bool {
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async {
                onChange()
            }
        }
        var address = Self.address
        guard AudioObjectAddPropertyListenerBlock(system, &address, queue, block) == noErr else { return false }
        self.block = block
        return true
    }

    nonisolated func remove() {
        guard let block else { return }
        var address = Self.address
        AudioObjectRemovePropertyListenerBlock(system, &address, queue, block)
        self.block = nil
    }

    static var address: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }
}
#endif

/// One watch for the default output. `shared` uses the hardware installer.
/// A test passes its own installer and never opens Core Audio.
@MainActor
final class DefaultOutputWatch {
    static let shared = DefaultOutputWatch(installer: DefaultOutputHardware.install)

    struct Token: Hashable, Sendable {
        fileprivate let id: UUID
    }

    private let book = DefaultOutputBook()
    private let installer: @Sendable (@escaping @Sendable () -> Void) -> DefaultOutputHandle

    init(installer: @escaping @Sendable (@escaping @Sendable () -> Void) -> DefaultOutputHandle) {
        self.installer = installer
    }

    func subscribe(_ handler: @escaping @Sendable () -> Void) -> Token {
        Token(id: book.subscribe(handler, install: installer))
    }

    func unsubscribe(_ token: Token) {
        book.unsubscribe(token.id)
    }

    /// Hops to the main actor, then subscribes on `shared`.
    nonisolated static func subscribe(_ handler: @escaping @Sendable () -> Void) async -> Token {
        await MainActor.run { shared.subscribe(handler) }
    }

    /// Hops to the main actor, then drops that subscription.
    nonisolated static func unsubscribe(_ token: Token) async {
        await MainActor.run { shared.unsubscribe(token) }
    }
}
