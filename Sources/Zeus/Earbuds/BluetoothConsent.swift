/// Lowest layer of the Bluetooth consent check.
/// `current` reads the class property and does not make a manager.
/// A request makes one manager only while that property is still not asked,
/// with the power alert off, and it does not ask for a scan.
/// A state change re-reads the class property and finishes only when that
/// is no longer not asked. `abandon` releases a held manager and then reads
/// the property at that moment. This file keeps no device name.
public enum BluetoothConsent {
    /// What a class-property read means. A code outside the four stays nil.
    public enum Access: Sendable, Equatable, Hashable, CaseIterable {
        case notAsked
        case restricted
        case denied
        case allowed
    }

    /// The class-property codes, in header order. There is no fifth.
    public enum ClassProperty: Int, Sendable, Equatable, Hashable, CaseIterable {
        case notDetermined = 0
        case restricted = 1
        case denied = 2
        case allowedAlways = 3
    }

    /// The only shape a manager is allowed to take. The alert stays off.
    public struct Options: Sendable, Equatable {
        public var showPowerAlert: Bool { false }

        /// A request does not ask for a scan.
        public var scans: Bool { false }

        public init() {}

        public static func == (lhs: Options, rhs: Options) -> Bool {
            lhs.showPowerAlert == rhs.showPowerAlert && lhs.scans == rhs.scans
        }
    }

    /// One read of the class property. It is the only question `current` asks.
    public struct ReadGate: Sendable {
        public var authorization: @Sendable () -> Int

        public init(authorization: @escaping @Sendable () -> Int) {
            self.authorization = authorization
        }
    }

    /// The maker runs once, and only while the property is still not asked and nothing is held.
    public struct MakeGate: Sendable {
        public var make: @Sendable (Options) -> Bool

        public init(make: @escaping @Sendable (Options) -> Bool) {
            self.make = make
        }
    }

    /// `release` runs only when a manager is held, and the read runs after it.
    public struct ReleaseGate: Sendable {
        public var release: @Sendable () -> Void
        public var authorization: @Sendable () -> Int

        public init(release: @escaping @Sendable () -> Void, authorization: @escaping @Sendable () -> Int) {
            self.release = release
            self.authorization = authorization
        }
    }

    /// Whether this call made a manager, and the class property it read.
    public struct Hold: Sendable, Equatable {
        public var created: Bool
        public var access: Access?

        public init(created: Bool, access: Access?) {
            self.created = created
            self.access = access
        }
    }

    /// A state callback. `finished` is true only for a decided grant.
    public struct Notice: Sendable, Equatable {
        public var finished: Bool
        public var access: Access?

        public init(finished: Bool, access: Access?) {
            self.finished = finished
            self.access = access
        }
    }

    /// What `abandon` did. The access is the class property after the release.
    public struct Released: Sendable, Equatable {
        public var released: Bool
        public var access: Access?

        public init(released: Bool, access: Access?) {
            self.released = released
            self.access = access
        }
    }

    /// Maps one class-property code. Any other integer is not a grant.
    public static func access(from raw: Int) -> Access? {
        switch ClassProperty(rawValue: raw) {
        case .notDetermined: return .notAsked
        case .restricted: return .restricted
        case .denied: return .denied
        case .allowedAlways: return .allowed
        case nil: return nil
        }
    }

    /// Reads the class property once. This call does not make a manager.
    public static func current(_ gate: ReadGate) -> Access? {
        access(from: gate.authorization())
    }

    /// One manager, or none. A decided grant, an unknown code, or a manager
    /// already held does not ask the maker. A refusal is not asked again
    /// inside this call. A second call starts from its own arguments.
    public static func request(_ read: ReadGate, held: Bool, _ make: MakeGate) -> Hold {
        let access = current(read)
        guard access == .notAsked, held == false else {
            return Hold(created: false, access: access)
        }
        let created = make.make(Options())
        return Hold(created: created, access: access)
    }

    /// Re-reads the class property. Finishes only when it is no longer not asked.
    /// An unknown code stays unfinished. This call does not make a manager.
    public static func stateChanged(_ read: ReadGate) -> Notice {
        let access = current(read)
        let finished = access != nil && access != .notAsked
        return Notice(finished: finished, access: access)
    }

    /// Releases a held manager, then reads the class property. An empty hold
    /// releases nothing and still reads. This call does not make a manager.
    public static func abandon(held: Bool, _ gate: ReleaseGate) -> Released {
        if held {
            gate.release()
        }
        return Released(released: held, access: access(from: gate.authorization()))
    }
}
