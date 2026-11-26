import Foundation

/// The registration book for the earbuds connect feed.
///
/// `start` asks whether access is allowed, then takes one connect registration.
/// A nil connect registration holds nothing. Each connected, paired audio device
/// then gets one disconnect registration. `watchDisconnect` and `unwatch` hold
/// or drop that one registration. `stop` drops every registration this book holds.
///
/// The live Bluetooth type stays out of this file. `copy` is the only value a
/// callback may carry across: the address, the name, and the class fields.
/// This file does not declare `BluetoothAccess` or `DeviceFacts`, and it does
/// not normalise an address.
public enum EarbudsBluetoothFeed {
    /// Bluetooth class-of-device numbers for audio earbuds. A loudspeaker,
    /// a microphone and a car kit are not in this set.
    public enum AudioClass {
        public static let major: UInt8 = 0x04
        public static let headset: UInt8 = 0x01
        public static let handsFree: UInt8 = 0x02
        public static let headphones: UInt8 = 0x06
    }

    /// Plain facts copied off a device object. Nothing else is kept.
    public struct Record: Sendable, Equatable {
        public var address: String
        public var name: String
        public var paired: Bool
        public var major: UInt8
        public var minor: UInt8
        public var connected: Bool

        public init(
            address: String, name: String, paired: Bool,
            major: UInt8, minor: UInt8, connected: Bool
        ) {
            self.address = address
            self.name = name
            self.paired = paired
            self.major = major
            self.minor = minor
            self.connected = connected
        }
    }

    /// What this book currently holds. `disconnects` keeps the first address
    /// of each device, in the order it was registered.
    public struct Book: Sendable, Equatable {
        public var connectHeld: Bool
        public var disconnects: [String]

        public init(connectHeld: Bool = false, disconnects: [String] = []) {
            self.connectHeld = connectHeld
            self.disconnects = disconnects
        }

        public static let empty = Book()
    }

    /// The questions `start` is allowed to ask. Each closure runs only when
    /// the rule reaches it. A false connect or disconnect answer is a nil
    /// registration.
    public struct Gate: Sendable {
        public var allowed: @Sendable () -> Bool
        public var registerConnect: @Sendable () -> Bool
        public var devices: @Sendable () -> [Record]
        public var registerDisconnect: @Sendable (String) -> Bool
        public var unregisterDisconnect: @Sendable (String) -> Void
        public var unregisterConnect: @Sendable () -> Void

        public init(
            allowed: @escaping @Sendable () -> Bool,
            registerConnect: @escaping @Sendable () -> Bool,
            devices: @escaping @Sendable () -> [Record],
            registerDisconnect: @escaping @Sendable (String) -> Bool,
            unregisterDisconnect: @escaping @Sendable (String) -> Void,
            unregisterConnect: @escaping @Sendable () -> Void
        ) {
            self.allowed = allowed
            self.registerConnect = registerConnect
            self.devices = devices
            self.registerDisconnect = registerDisconnect
            self.unregisterDisconnect = unregisterDisconnect
            self.unregisterConnect = unregisterConnect
        }
    }

    public enum Start: Sendable, Equatable {
        /// Access is not allowed, or the book already holds a disconnect
        /// registration without a connect registration. Nothing was asked.
        case refused
        /// The connect registration came back nil. Nothing is held.
        case failed
        /// One connect registration, and one disconnect registration for each
        /// returned device.
        case started(Book, devices: [Record])
        /// A connect registration is already held. Nothing was asked again.
        case already(Book)
    }

    public enum Watch: Sendable, Equatable {
        /// Not watching, a blank address, or that address is already held.
        case ignored
        case held
        /// The disconnect registration came back nil. The address is not held.
        case missed
    }

    /// A callback may carry this copy and nothing read off the device later.
    public static func copy(_ record: Record) -> Record {
        Record(
            address: record.address,
            name: record.name,
            paired: record.paired,
            major: record.major,
            minor: record.minor,
            connected: record.connected
        )
    }

    /// Connected, paired, audio, and one of the three earbud minors.
    /// A blank address does not qualify. The address bytes are not rewritten.
    public static func qualifies(_ record: Record) -> Bool {
        guard usableAddress(record.address) else { return false }
        guard record.paired, record.connected else { return false }
        guard record.major == AudioClass.major else { return false }
        switch record.minor {
        case AudioClass.headset, AudioClass.handsFree, AudioClass.headphones:
            return true
        default:
            return false
        }
    }

    /// Takes one connect registration when access is allowed and this book
    /// holds none. Devices that do not qualify are not registered. Each address
    /// is asked once, including when that registration comes back nil. A nil
    /// disconnect registration skips that device and leaves the connect
    /// registration held.
    public static func start(_ book: Book, _ gate: Gate) -> (Start, Book) {
        if book.connectHeld {
            return (.already(book), book)
        }
        if !book.disconnects.isEmpty {
            return (.refused, book)
        }
        guard gate.allowed() else {
            return (.refused, book)
        }
        guard gate.registerConnect() else {
            return (.failed, book)
        }
        var seen: [String] = []
        var disconnects: [String] = []
        var devices: [Record] = []
        for record in gate.devices() {
            let copied = copy(record)
            guard qualifies(copied), !seen.contains(copied.address) else { continue }
            seen.append(copied.address)
            guard gate.registerDisconnect(copied.address) else { continue }
            disconnects.append(copied.address)
            devices.append(copied)
        }
        let next = Book(connectHeld: true, disconnects: disconnects)
        return (.started(next, devices: devices), next)
    }

    /// Holds one disconnect registration for `address` while a connect
    /// registration is already held. A second call for the same address
    /// registers nothing.
    public static func watchDisconnect(_ book: Book, address: String, _ gate: Gate) -> (Watch, Book) {
        guard book.connectHeld, usableAddress(address), !book.disconnects.contains(address) else {
            return (.ignored, book)
        }
        guard gate.registerDisconnect(address) else {
            return (.missed, book)
        }
        var next = book
        next.disconnects.append(address)
        return (.held, next)
    }

    /// Drops the disconnect registration for `address` when this book holds it.
    /// An address that is not held is left alone. The connect registration stays.
    public static func unwatch(_ book: Book, address: String, _ gate: Gate) -> Book {
        guard book.disconnects.contains(address) else { return book }
        gate.unregisterDisconnect(address)
        var next = book
        next.disconnects.removeAll { $0 == address }
        return next
    }

    /// Drops the connect registration, then each disconnect registration, in
    /// the order they were held. A book that holds nothing asks for nothing.
    public static func stop(_ book: Book, _ gate: Gate) -> Book {
        if !book.connectHeld && book.disconnects.isEmpty {
            return .empty
        }
        if book.connectHeld {
            gate.unregisterConnect()
        }
        for address in book.disconnects {
            gate.unregisterDisconnect(address)
        }
        return .empty
    }

    private static func usableAddress(_ address: String) -> Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
