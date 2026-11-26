/// Lowest layer of the speaker browser. The two declared types live only here.
/// A start asks for one browse of each type, on the default domain, with peer-to-peer off.
/// A cancel asks once for each declared type that opened with those parameters.
/// A refusal is kept and is not asked again. This file keeps no announced name.
public enum SpeakerBrowser {
    /// The only two types. There is no third.
    public enum Service: String, Sendable, Equatable, Hashable, CaseIterable {
        case airplay = "_airplay._tcp"
        case raop = "_raop._tcp"
    }

    /// AirPlay, then RAOP.
    public static let declared: [Service] = [.airplay, .raop]

    /// A browse descriptor. The domain `nil` is the system default.
    public enum Descriptor: Sendable, Equatable {
        case bonjourTXT(type: String, domain: String?)
    }

    /// What one browse is allowed to ask for. Peer-to-peer stays off.
    public struct Parameters: Sendable, Equatable {
        public var descriptor: Descriptor

        public var includePeerToPeer: Bool { false }

        public init(descriptor: Descriptor) {
            self.descriptor = descriptor
        }
    }

    /// One declared type after a start. `opened` is false when the maker refused.
    public struct Slot: Sendable, Equatable {
        public var service: Service
        public var parameters: Parameters
        public var opened: Bool

        public init(service: Service, parameters: Parameters, opened: Bool) {
            self.service = service
            self.parameters = parameters
            self.opened = opened
        }
    }

    /// The maker runs once per declared type. It is the only request a start sends.
    public struct MakeGate: Sendable {
        public var make: @Sendable (Parameters) -> Bool

        public init(make: @escaping @Sendable (Parameters) -> Bool) {
            self.make = make
        }
    }

    /// Cancel runs once per opened declared type. It is the only request a cancel sends.
    public struct CancelGate: Sendable {
        public var cancel: @Sendable (Service) -> Void

        public init(cancel: @escaping @Sendable (Service) -> Void) {
            self.cancel = cancel
        }
    }

    /// The parameters a browse of `service` is allowed to use.
    public static func parameters(for service: Service) -> Parameters {
        Parameters(descriptor: .bonjourTXT(type: service.rawValue, domain: nil))
    }

    /// Exact match against the two declared types. A longer string, a newline, or NUL is nil.
    public static func service(named type: String) -> Service? {
        let bytes = Array(type.utf8)
        let limit = declared.map { $0.rawValue.utf8.count }.max() ?? 0
        if bytes.count > limit { return nil }
        if bytes.contains(0) || bytes.contains(UInt8(ascii: "\n")) || bytes.contains(UInt8(ascii: "\r")) {
            return nil
        }
        let text = String(decoding: bytes, as: UTF8.self)
        return declared.first { $0.rawValue == text }
    }

    /// One browse per declared type, in declared order. A refusal does not add another type.
    /// A second call starts empty.
    public static func start(_ gate: MakeGate) -> [Slot] {
        declared.map { service in
            let shaped = parameters(for: service)
            let opened = gate.make(shaped)
            return Slot(service: service, parameters: shaped, opened: opened)
        }
    }

    /// Cancels each opened declared type once, in declared order.
    /// A slot whose parameters differ from `parameters(for:)` is left alone.
    public static func cancel(_ slots: [Slot], _ gate: CancelGate) -> [Service] {
        var opened = Set<Service>()
        for slot in slots where slot.opened && slot.parameters == parameters(for: slot.service) {
            opened.insert(slot.service)
        }
        var cancelled: [Service] = []
        for service in declared where opened.contains(service) {
            gate.cancel(service)
            cancelled.append(service)
        }
        return cancelled
    }
}

#if canImport(Network)
import Foundation
@preconcurrency import Network

extension SpeakerBrowser {
    /// Live browsers for the two declared types. Peer-to-peer stays off.
    /// This type is not main-actor isolated. A second start leaves the open browsers in place.
    public final class Live: @unchecked Sendable {
        private let queue = DispatchQueue(label: "app.zeus.speaker-browser")
        private let lock = NSLock()
        private var browsers: [NWBrowser] = []

        public init() {}

        /// One browser per declared type. A descriptor outside the gate is not started.
        public func start() {
            lock.lock()
            defer { lock.unlock() }
            guard browsers.isEmpty else { return }
            var made: [NWBrowser] = []
            for service in declared {
                let shaped = parameters(for: service)
                guard case .bonjourTXT(let type, let domain) = shaped.descriptor,
                      type == service.rawValue,
                      domain == nil,
                      shaped.includePeerToPeer == false
                else { return }
                let parameters = NWParameters()
                parameters.includePeerToPeer = shaped.includePeerToPeer
                let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: domain), using: parameters)
                made.append(browser)
            }
            guard made.count == declared.count else { return }
            browsers = made
            for browser in made {
                browser.start(queue: queue)
            }
        }

        /// Cancels each open browser once and keeps none.
        public func cancel() {
            lock.lock()
            defer { lock.unlock() }
            let open = browsers
            browsers = []
            for browser in open {
                browser.cancel()
            }
        }
    }
}
#endif
