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

    /// Outbound: we start the pairing.
    init(endpoint: FlingEndpoint, initiatorTo address: NWEndpoint, expectedID: String?) {
        self.endpoint = endpoint
        self.role = .initiator
        self.number = nil
        self.expectedID = expectedID
        self.channel = FlingChannel(connection: NWConnection(to: address, using: endpoint.pairingClientParameters()), queue: endpoint.queue)
    }

    /// Inbound: someone connected to our pairing port.
    init(endpoint: FlingEndpoint, inbound connection: NWConnection, number: Int) {
        self.endpoint = endpoint
        self.role = .responder
        self.number = number
        self.expectedID = nil
        self.channel = FlingChannel(connection: connection, queue: endpoint.queue)
    }

    func start() {
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
            channel.handshaken = true
            if let expectedID, expectedID != hello.id { return end(.failed(.unexpectedMessage)) }
            if role == .responder {
                if endpoint.mute.isMuted(hello.id, now: Date()) { return abort() }
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
        for effect in effects {
            switch effect {
            case .send(let message): channel.send(message)
            case .showCode(let code, let role):
                endpoint.emit(.pairCode(code: code, role: role, peerID: remote.id, peerName: remote.name))
            case .storePSK(let peerID, let psk):
                if endpoint.store.add(id: peerID, name: remote.name, model: remote.model, psk: psk, now: Date()) {
                    endpoint.peerPaired()
                    endpoint.emit(.paired(peerID: peerID, name: remote.name))
                } else {
                    endpoint.emit(.pairEnded(.failed(.badConfirm)))
                }
            case .hidePrompt: break
            case .close: channel.closeAfterFlush()
            }
        }
        if let state = machine?.state, state.isFinal { end(state) }
    }

    private func end(_ state: FlingPairingState) {
        guard !finished else { return }
        if state != .confirmed { endpoint.emit(.pairEnded(state)) }
        if state == .declined, role == .responder, let remote { endpoint.mute.recordDecline(remote.id, now: Date()) }
        channel.closeAfterFlush()
        finish()
    }

    private func closed() {
        guard !finished else { return }
        if var m = machine { let out = m.handle(.connectionLost); machine = m; apply(out) } else { finish() }
    }

    func answer(accept: Bool) {
        guard !finished, var m = machine else { return }
        let event: FlingPairingEvent = role == .responder ? (accept ? .userAccept : .userDecline) : .userCancel
        let out = m.handle(event)
        machine = m
        apply(out)
    }

    func tick(_ now: Date) {
        guard !finished, var m = machine else { return }
        let out = m.handle(.tick(now: now))
        machine = m
        if !out.isEmpty { apply(out) }
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
        if let number { endpoint.gate.release(connection: number) }
        endpoint.forget(self)
    }
}
