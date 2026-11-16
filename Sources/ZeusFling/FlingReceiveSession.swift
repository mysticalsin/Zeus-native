import Foundation
import Network
import Security
import ZeusCore

/// One inbound transfer connection. The TLS handshake already proved the peer holds a paired key; this drives the
/// receive machine over the frames and does the disk work the machine asks for.
final class FlingReceiveSession {
    private unowned let endpoint: FlingEndpoint
    private let channel: FlingChannel
    private let number: Int
    private var machine: FlingReceiveMachine?
    private var sink: FlingFileSink?
    private var offer: FlingOffer?
    private var peer: FlingHello?
    private var peerID: String?
    private var nonce = ""
    private var committed: [Int: URL] = [:]
    private var totalBytes: Int64 = 0
    private var doneBytes: Int64 = 0
    private var lastProgress = Date.distantPast
    private var finished = false
    private var holdsTransfer = false
    private var announcedEnd = false
    /// Where the person chose to put these files when the mode is Ask each time.
    private var chosenMode: FlingSaveMode?

    var stackID: UUID? { offer?.stackID }

    init(endpoint: FlingEndpoint, channel: FlingChannel, number: Int) {
        self.endpoint = endpoint
        self.channel = channel
        self.number = number
    }

    func start() {
        channel.onReady = { [self] in
            // The hello carries a fresh nonce; the sender must answer with a proof made with the key of the id it claims.
            var bytes = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            nonce = Data(bytes).base64EncodedString()
            channel.send(.hello(FlingHello(id: endpoint.identity.id, name: endpoint.identity.name, model: endpoint.identity.model, nonce: nonce)))
        }
        channel.onFrame = { [self] frame in handle(frame) }
        channel.onClose = { [self] reason in closed(reason) }
        channel.start()
    }

    private func closed(_ reason: FlingCloseReason) {
        guard !finished else { return }
        if !channel.becameReady {
            // The handshake never completed: an unknown key, a wrong key, or a peer that is not Fling.
            var why = "tls"
            if case .failed(let error) = reason, case .tls(let status) = error { why = status == -9864 ? "notPaired" : "badKey" }
            endpoint.emit(.rejected(reason: why, via: "tls"))
            return finish()
        }
        if var m = machine {
            let out = m.handle(.connectionLost)
            machine = m
            apply(out)
        }
        finish()
    }

    private func handle(_ frame: FlingFrame) {
        guard !finished else { return }
        guard let message = try? FlingWire.decode(frame) else { return fail() }
        guard let peer else {
            guard case .hello(let hello) = message else { return fail() }
            // The claimed id must be proved with that id's own key, bound to this connection's nonce. Which key the TLS
            // handshake used does not decide who the peer is, so a paired Mac cannot pose as another paired Mac.
            guard let key = endpoint.store.psk(for: hello.id) else {
                endpoint.emit(.rejected(reason: "notPaired", via: "hello"))
                return fail()
            }
            guard let proof = hello.proof, FlingCrypto.isValidHelloProof(proof, psk: key, nonce: nonce, id: hello.id) else {
                endpoint.emit(.rejected(reason: "idMismatch", via: "hello"))
                return fail()
            }
            self.peer = hello
            peerID = hello.id
            channel.handshaken = true
            endpoint.store.touch(id: hello.id, now: Date())
            return
        }
        if machine == nil {
            guard case .offer(let incoming) = message else { return fail() }
            beginMachine(offer: incoming, peer: peer)
            return
        }
        switch message {
        case .chunk, .fileDone, .cancel:
            apply(step(.received(message, now: Date())))
        default:
            fail()
        }
    }

    private func beginMachine(offer incoming: FlingOffer, peer: FlingHello) {
        guard endpoint.gate.beginTransfer(peerID: peer.id) else {
            channel.send(.decline(FlingDecline(stackID: incoming.stackID, reason: .busy)))
            channel.closeAfterFlush()
            return finish()
        }
        holdsTransfer = true
        offer = incoming
        totalBytes = FlingOfferRules.totalFileBytes(incoming)
        let name = endpoint.store.pairedNames()[peer.id] ?? peer.name
        let place = FlingSaveRules.destination(mode: endpoint.settings.saveMode, root: endpoint.saveRoot, inbox: endpoint.inbox, peer: name, date: Date(),
                                               downloadsGranted: endpoint.settings.downloadsGranted).deletingLastPathComponent()
        let context = FlingReceiveContext(peerID: peer.id, peerName: name, paired: true, autoAccept: endpoint.settings.autoAcceptPaired && endpoint.settings.saveMode != .ask,
                                          freeBytes: endpoint.freeBytes(at: place), isReplay: endpoint.replay.isReplay(incoming.stackID, now: Date()))
        machine = FlingReceiveMachine(context: context)
        apply(step(.received(.offer(incoming), now: Date())))
    }

    private func step(_ event: FlingReceiveEvent) -> [FlingReceiveEffect] {
        guard var m = machine else { return [] }
        let out = m.handle(event)
        machine = m
        return out
    }

    private var peerName: String { peer.map { endpoint.store.pairedNames()[$0.id] ?? $0.name } ?? "Mac" }

    private func apply(_ effects: [FlingReceiveEffect]) {
        var queue = effects
        while !queue.isEmpty {
            let effect = queue.removeFirst()
            switch effect {
            case .send(let message): channel.send(message)
            case .makeTemp(let id):
                endpoint.reserved[id] = totalBytes
                let destination = FlingSaveRules.destination(mode: chosenMode ?? endpoint.settings.saveMode, root: endpoint.saveRoot, inbox: endpoint.inbox,
                                                              peer: peerName, date: Date(), downloadsGranted: endpoint.settings.downloadsGranted)
                let sink = FlingFileSink(stackID: id, partialParent: destination.deletingLastPathComponent(), destination: destination)
                self.sink = sink
                do { try sink.makeTemp() } catch { queue += step(.commitFailed(index: 0)) }
            case .write(let index, let data):
                do {
                    try sink?.write(index: index, data: data)
                    doneBytes += Int64(data.count)
                    emitProgress()
                } catch { queue += step(.commitFailed(index: index)) }
            case .verify(let index):
                do { queue += step(.hashComputed(index: index, sha256: try sink?.verify(index: index) ?? "")) }
                catch { queue += step(.commitFailed(index: index)) }
            case .commit(let index):
                guard let name = offer?.items.first(where: { $0.index == index })?.name else { break }
                do { committed[index] = try sink?.commit(index: index, name: name); queue += step(.committed(index: index)) }
                catch { queue += step(.commitFailed(index: index)) }
            case .commitLink(let index, let url):
                guard let name = offer?.items.first(where: { $0.index == index })?.name else { break }
                do { committed[index] = try sink?.commitLink(name: name, link: url); queue += step(.committed(index: index)) }
                catch { queue += step(.commitFailed(index: index)) }
            case .addToShelf(let index):
                guard let item = offer?.items.first(where: { $0.index == index }), let url = committed[index], let id = offer?.stackID else { break }
                endpoint.emit(.itemArrived(stackID: id, index: index, name: url.lastPathComponent, url: url, sha256: item.sha256,
                                           peerName: peerName, link: item.kind == .link ? item.url : nil))
            case .deleteTemp: sink?.deleteTemp()
            case .prompt(let name, let count, let total, let id):
                endpoint.emit(.offer(stackID: id, peerID: peer?.id ?? "", peerName: name, itemCount: count, totalBytes: total))
            case .hidePrompt: break
            case .close: channel.closeAfterFlush()
            }
        }
        announceIfFinal()
    }

    private func emitProgress() {
        guard let id = offer?.stackID else { return }
        let now = Date()
        if now.timeIntervalSince(lastProgress) > 0.1 || doneBytes >= totalBytes {
            lastProgress = now
            endpoint.emit(.progress(stackID: id, direction: .receive, done: doneBytes, total: totalBytes))
        }
    }

    private func announceIfFinal() {
        guard let state = machine?.state, state.isFinal, !announcedEnd, let id = offer?.stackID else { return }
        announcedEnd = true
        switch state {
        case .done:
            sink?.finish()
            endpoint.emit(.stackFinished(stackID: id, direction: .receive))
        case .declined(let reason): endpoint.emit(.declined(stackID: id, direction: .receive, reason: reason))
        case .cancelled: endpoint.emit(.cancelled(stackID: id, direction: .receive))
        case .failed(let failure):
            switch failure {
            case .badName: endpoint.emit(.declined(stackID: id, direction: .receive, reason: .badName))
            case .tooMany: endpoint.emit(.declined(stackID: id, direction: .receive, reason: .tooMany))
            case .diskFull: endpoint.emit(.declined(stackID: id, direction: .receive, reason: .diskFull))
            case .notPaired: endpoint.emit(.declined(stackID: id, direction: .receive, reason: .notPaired))
            case .replay: endpoint.emit(.declined(stackID: id, direction: .receive, reason: .replay))
            case .malformed: endpoint.emit(.declined(stackID: id, direction: .receive, reason: .malformed))
            case .badLink: endpoint.emit(.declined(stackID: id, direction: .receive, reason: .badLink))
            case .overSize: endpoint.emit(.declined(stackID: id, direction: .receive, reason: .overSize))
            case .hashMismatch: endpoint.emit(.failed(stackID: id, direction: .receive, reason: "hashMismatch"))
            case .peerLost: endpoint.emit(.failed(stackID: id, direction: .receive, reason: "peerLost"))
            }
        default: break
        }
    }

    func answer(accept: Bool, mode: FlingSaveMode? = nil) {
        if accept { chosenMode = mode }
        apply(step(accept ? .userAccept : .userDecline))
    }
    func cancel() { apply(step(.userCancel)) }

    func tick(_ now: Date) {
        guard !finished else { return }
        apply(step(.tick(now: now)))
        // A prompt can wait 60 s for the person; that is not idleness.
        if case .prompting = machine?.state { channel.lastActivity = now }
        if FlingTimeoutPolicy(connectedAt: channel.connectedAt, lastActivity: channel.lastActivity).shouldClose(now: now, handshaken: channel.handshaken) {
            if var m = machine, !m.state.isFinal { let out = m.handle(.connectionLost); machine = m; apply(out) }
            abort()
        }
    }

    func abort() {
        if var m = machine, !m.state.isFinal {
            let out = m.handle(.userCancel)
            machine = m
            for effect in out { if case .deleteTemp = effect { sink?.deleteTemp() } }
            announceIfFinal()
        }
        sink?.deleteTemp()
        channel.cancel()
        finish()
    }

    private func fail() {
        if var m = machine, !m.state.isFinal { let out = m.handle(.connectionLost); machine = m; apply(out) }
        channel.cancel()
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        if let id = offer?.stackID { endpoint.reserved[id] = nil }
        if holdsTransfer, let peerID = peer?.id { endpoint.gate.endTransfer(peerID: peerID) }
        endpoint.gate.release(connection: number)
        endpoint.forget(self)
    }
}
