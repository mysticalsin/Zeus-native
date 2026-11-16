import Foundation
import Network
import ZeusCore

/// One pairing conversation on the plain pairing port. It also answers anything that is not a pairing frame
/// with "not paired", which is all a stranger can get from this port.
final class FlingPairSession {
    private unowned let endpoint: FlingEndpoint
    private let channel: FlingChannel
    private let role: FlingPairRole
    private let number: Int?
    private let expectedID: String?
    private var machine: FlingPairingMachine?
    private var remote: FlingHello?
    private var helloReceived = false
    private var holdsGate = false
    private var finished = false
    private var helloAt: Date?
    private let address: String

    /// Outbound: we start the pairing.
    init(endpoint: FlingEndpoint, initiatorTo address: NWEndpoint, expectedID: String?) {
        self.endpoint = endpoint
        self.role = .initiator
        self.number = nil
        self.expectedID = expectedID
        self.address = "out"
        self.channel = FlingChannel(connection: NWConnection(to: address, using: endpoint.pairingClientParameters()), queue: endpoint.queue)
    }

    /// Inbound: someone connected to our pairing port.
    init(endpoint: FlingEndpoint, inbound connection: NWConnection, number: Int) {
        self.endpoint = endpoint
        self.role = .responder
        self.number = number
        self.expectedID = nil
        self.address = Self.hostText(connection.endpoint)
        self.channel = FlingChannel(connection: connection, queue: endpoint.queue)
    }

    /// The remote host without an interface suffix, for rate limiting.
    private static func hostText(_ endpoint: NWEndpoint) -> String {
        if case .hostPort(let host, _) = endpoint {
            return "\(host)".split(separator: "%").first.map(String.init) ?? "\(host)"
        }
        return "unknown"
    }

    func start() {
        if role == .responder && endpoint.mute.isMuted("", address: address, now: Date()) { return abort() }
        channel.onReady = { [self] in sendHello() }
        channel.onFrame = { [self] frame in handle(frame) }
        channel.onClose = { [self] _ in closed() }
        channel.start()
    }

    private func sendHello() {
        channel.send(.hello(FlingHello(id: endpoint.identity.id, name: endpoint.identity.name, model: endpoint.identity.model)))
    }

    private func handle(_ frame: FlingFrame) {
        guard !finished else { return }
        guard let message = try? FlingWire.decode(frame) else { return reject("malformed") }
        if !helloReceived {
            guard case .hello(let hello) = message else { return rejectStranger(message) }
            helloReceived = true
            remote = hello
            helloAt = Date()
            channel.handshaken = true
            if let expectedID, expectedID != hello.id { return end(.failed(.unexpectedMessage)) }
            // A Mac that already has a key here is never paired over: remove it in Settings first.
            if endpoint.store.isPaired(hello.id) {
                channel.send(.pairDecline(FlingPairDecline(reason: "alreadyPaired")))
                endpoint.emit(.pairEnded(.failed(.alreadyPaired)))
                channel.closeAfterFlush()
                return finish()
            }
            if role == .responder {
                if endpoint.mute.isMuted(hello.id, address: address, now: Date()) { return abort() }
                guard endpoint.promptGate.tryBegin(hello.id) else {
                    channel.send(.pairDecline(FlingPairDecline(reason: "busy")))
                    return channel.closeAfterFlush()
                }
                holdsGate = true
                channel.send(.hello(FlingHello(id: endpoint.identity.id, name: endpoint.identity.name, model: endpoint.identity.model)))
            }
            let entropy = FlingPairingEntropy.random()
            machine = FlingPairingMachine(role: role, localID: endpoint.identity.id, remoteID: hello.id, entropy: entropy)
            if role == .initiator { apply(machine?.handle(.start(now: Date())) ?? []) }
            return
        }
        switch message {
        case .pairCommit, .pairKey, .pairReveal, .pairConfirm, .pairDecline:
            apply(machine?.handle(.received(message, now: Date())) ?? [])
        case .hello:
            break
        default:
            rejectStranger(message)
        }
    }

    /// An offer or any other non-pairing frame on the pairing port.
    private func rejectStranger(_ message: FlingMessage) {
        endpoint.emit(.rejected(reason: "notPaired", via: "pairing"))
        if case .offer(let offer) = message { channel.send(.decline(FlingDecline(stackID: offer.stackID, reason: .notPaired))) }
        channel.closeAfterFlush()
        finish()
    }

    private func reject(_ reason: String) {
        endpoint.emit(.rejected(reason: reason, via: "pairing"))
        channel.cancel()
        finish()
    }

    private func apply(_ effects: [FlingPairingEffect]) {
        guard let remote else { return }
        // The key is stored after the confirmation has been handed to the connection, so a send that fails never
        // leaves this Mac paired with a Mac that was not told.
        let lastSend = effects.lastIndex { if case .send = $0 { true } else { false } }
        let storeAt = effects.firstIndex { if case .storePSK = $0 { true } else { false } }
        for (index, effect) in effects.enumerated() {
            switch effect {
            case .send(let message):
                if let storeAt, index == lastSend, index < storeAt, case .storePSK(let peerID, let psk) = effects[storeAt] {
                    channel.send(message) { [self] error in
                        if error == nil { store(peerID: peerID, psk: psk, remote: remote) } else { end(.failed(.connectionLost)) }
                    }
                } else {
                    channel.send(message)
                }
            case .showCode(let code, let role):
                endpoint.emit(.pairCode(code: code, role: role, peerID: remote.id, peerName: remote.name))
            case .storePSK(let peerID, let psk):
                // With a confirmation ahead of it, the send's completion stores the key instead.
                if !(lastSend.map { $0 < index } ?? false) { store(peerID: peerID, psk: psk, remote: remote) }
            case .hidePrompt: break
            case .close: channel.closeAfterFlush()
            }
        }
        if let state = machine?.state, state.isFinal { end(state) }
    }

    private func store(peerID: String, psk: Data, remote: FlingHello) {
        if endpoint.store.add(id: peerID, name: remote.name, model: remote.model, psk: psk, now: Date()) {
            endpoint.peerPaired()
            endpoint.emit(.paired(peerID: peerID, name: remote.name))
        } else {
            endpoint.emit(.pairEnded(.failed(endpoint.store.isPaired(peerID) ? .alreadyPaired : .badConfirm)))
        }
    }

    private func end(_ state: FlingPairingState) {
        guard !finished else { return }
        if state != .confirmed {
            endpoint.emit(.pairEnded(state))
            // Every attempt that did not end in a pairing counts, whatever id it came with.
            if role == .responder, let remote { endpoint.mute.recordFailure(remote.id, address: address, now: Date()) }
        }
        channel.closeAfterFlush()
        finish()
    }

    private func closed() {
        guard !finished else { return }
        if role == .responder, let remote, machine?.state.isFinal == false { endpoint.mute.recordFailure(remote.id, address: address, now: Date()) }
        if var m = machine { let out = m.handle(.connectionLost); machine = m; apply(out) } else { finish() }
    }

    func answer(accept: Bool, peerID: String?) {
        guard !finished, var m = machine else { return }
        if let peerID, remote?.id != peerID { return }
        let event: FlingPairingEvent = accept ? .userAccept : (role == .responder ? .userDecline : .userCancel)
        let out = m.handle(event)
        machine = m
        apply(out)
    }

    func tick(_ now: Date) {
        guard !finished else { return }
        // A connection that never says hello is closed after the handshake time, whatever else is going on.
        if !channel.handshaken, FlingTimeoutPolicy(connectedAt: channel.connectedAt, lastActivity: channel.lastActivity).shouldClose(now: now, handshaken: false) {
            return abort()
        }
        guard var m = machine else { return }
        let out = m.handle(.tick(now: now))
        machine = m
        if !out.isEmpty { apply(out) }
        // After the hello each step before the code must arrive in time, so a silent peer cannot hold a slot or the card.
        if let helloAt, let state = machine?.state, now.timeIntervalSince(helloAt) > FlingLimits.pairingStageTimeout {
            switch state {
            case .idle, .committing, .awaitingKey, .awaitingReveal:
                if role == .responder, let remote { endpoint.mute.recordFailure(remote.id, address: address, now: now) }
                endpoint.emit(.pairEnded(.failed(.timedOut)))
                return abort()
            default: break
            }
        }
        // The code has its own 60 s deadline in the machine; only the handshake needs a cap here.
        if !channel.handshaken, FlingTimeoutPolicy(connectedAt: channel.connectedAt, lastActivity: channel.lastActivity).shouldClose(now: now, handshaken: false) {
            abort()
        }
    }

    func abort() {
        channel.cancel()
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        if holdsGate { endpoint.promptGate.end(); holdsGate = false }
        if let number { endpoint.pairGate.release(connection: number) }
        endpoint.forget(self)
    }
}
