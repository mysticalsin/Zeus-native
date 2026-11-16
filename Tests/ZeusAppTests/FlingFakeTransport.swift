import Foundation
import ZeusCore
import ZeusFling
@testable import Zeus

/// A transport that records what the service asks of it, so no network is involved.
final class FakeTransport: FlingTransporting, @unchecked Sendable {
    let events: AsyncStream<FlingEvent>
    private let continuation: AsyncStream<FlingEvent>.Continuation
    private let lock = NSLock()
    private(set) var starts = 0, stops = 0
    private(set) var sends: [(items: [FlingOutgoingItem], to: String)] = []
    private(set) var pairs: [String] = []
    private(set) var pairingAnswers: [Bool] = []
    private(set) var offerAnswers: [(UUID, Bool)] = []
    private(set) var modeAnswers: [(stack: UUID, accept: Bool, mode: FlingSaveMode?)] = []
    var paired: [FlingPairedPeer] = []
    /// When true, `removePeer` fails the way a locked Keychain does and the record stays.
    var removeFails = false

    init() {
        var c: AsyncStream<FlingEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { c = $0 }
        continuation = c
    }
    func emit(_ event: FlingEvent) { continuation.yield(event) }
    func start() { lock.lock(); starts += 1; lock.unlock() }
    func stop() { lock.lock(); stops += 1; lock.unlock() }
    func updateSettings(_ settings: FlingEndpointSettings) {}
    func pair(with address: FlingPeerAddress) { lock.lock(); pairs.append(address.id); lock.unlock() }
    func answerPairing(accept: Bool) { lock.lock(); pairingAnswers.append(accept); lock.unlock() }
    func send(_ items: [FlingOutgoingItem], to address: FlingPeerAddress) -> UUID {
        lock.lock(); sends.append((items, address.id)); lock.unlock(); return UUID()
    }
    func cancel(_ stackID: UUID) {}
    func answerOffer(_ stackID: UUID, accept: Bool, saveMode: FlingSaveMode?) {
        lock.lock(); offerAnswers.append((stackID, accept)); modeAnswers.append((stackID, accept, saveMode)); lock.unlock()
    }
    func removePeer(id: String) -> Bool {
        if removeFails { return false }
        paired.removeAll { $0.id == id }; return true
    }
    func address(of id: String) -> FlingPeerAddress? { FlingPeerAddress.direct(id: id, name: id, port: 1, pairPort: 2) }
    var pairedPeers: [FlingPairedPeer] { paired }
}
