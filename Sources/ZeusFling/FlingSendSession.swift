import Foundation
import Network
import UniformTypeIdentifiers
import ZeusCore

/// One outgoing stack. Hashes are taken first, then the connection opens and the offer goes out.
final class FlingSendSession {
    private unowned let endpoint: FlingEndpoint
    private let stackID: UUID
    private let address: FlingPeerAddress
    private let outgoing: [FlingOutgoingItem]
    private var machine: FlingSendMachine
    private var urls: [Int: URL] = [:]
    private var links: [Int: String] = [:]
    private var channel: FlingChannel?
    private var pending: [FlingMessage] = []
    private var sentBytes: Int64 = 0
    private var totalBytes: Int64 = 0
    private var lastProgress = Date.distantPast
    private var announced = false
    private var finished = false
    private var tlsRejected = false
    private var offerSentAt: Date?
    private let hashQueue = DispatchQueue(label: "zeus.fling.hash", qos: .utility)

    init(endpoint: FlingEndpoint, stackID: UUID, address: FlingPeerAddress, items: [FlingOutgoingItem]) {
        self.endpoint = endpoint
        self.stackID = stackID
        self.address = address
        self.outgoing = items
        self.machine = FlingSendMachine(stackID: stackID, items: [])
    }

    func start() {
        guard !outgoing.isEmpty, outgoing.count <= FlingLimits.maxItems else { return failEarly("tooMany") }
        guard let transfer = address.transfer else { return failEarly("noAddress") }
        let key: Data
        if endpoint.hooks.forceUnknownKey {
            key = Data(repeating: 0x5A, count: 32)
        } else if let stored = endpoint.store.psk(for: address.id) {
            key = stored
        } else {
            return failEarly("notPaired")
        }
        var items: [FlingSendItem] = []
        for (index, item) in outgoing.enumerated() {
            switch item.content {
            case .file(let url):
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return failEarly("missingFile") }
                guard !isDirectory.boolValue else { return failEarly("folder") }
                let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
                urls[index] = url
                totalBytes += size
                items.append(FlingSendItem(index: index, name: url.lastPathComponent, size: size, kind: .file,
                                           uti: UTType(filenameExtension: url.pathExtension)?.identifier, url: nil))
            case .link(let text):
                guard FlingOfferRules.isWebLink(text) else { return failEarly("badLink") }
                links[index] = text
                items.append(FlingSendItem(index: index, name: URL(string: text)?.host ?? "Link", size: 0, kind: .link, uti: nil, url: text))
            }
        }
        machine = FlingSendMachine(stackID: stackID, items: items)
        connectionTarget = transfer
        connectionKey = key
        apply(step(.start))
    }

    private var connectionTarget: NWEndpoint?
    private var connectionKey = Data()

    private func failEarly(_ reason: String) {
        endpoint.emit(.failed(stackID: stackID, direction: .send, reason: reason))
        finished = true
        announced = true
        endpoint.forget(sendStack: stackID)
    }

    private func step(_ event: FlingSendEvent) -> [FlingSendEffect] {
        let out = machine.handle(event)
        return out
    }

    private func apply(_ effects: [FlingSendEffect]) {
        var queue = effects
        while !queue.isEmpty {
            let effect = queue.removeFirst()
            switch effect {
            case .computeHash(let index): computeHash(index)
            case .send(let message): deliver(message)
            case .streamFile(let index): stream(index)
            case .close: channel?.closeAfterFlush()
            }
        }
        announceIfFinal()
    }

    private func computeHash(_ index: Int) {
        let url = urls[index], link = links[index]
        hashQueue.async { [weak self] in
            var hex = ""
            if let link {
                hex = FlingCrypto.sha256Hex(Data(link.utf8))
            } else if let url, let handle = try? FileHandle(forReadingFrom: url) {
                var hasher = FlingHasher()
                while let data = try? handle.read(upToCount: 1 << 20), !data.isEmpty { hasher.update(data) }
                try? handle.close()
                hex = hasher.finalHex()
            }
            guard let self else { return }
            self.endpoint.queue.async {
                guard !self.finished else { return }
                self.apply(self.step(.hashReady(index: index, sha256: hex)))
            }
        }
    }

    private func deliver(_ message: FlingMessage) {
        var message = message
        if case .offer(var offer) = message {
            if let raw = endpoint.hooks.rawName, !offer.items.isEmpty { offer.items[0].name = raw }
            message = .offer(offer)
            offerSentAt = Date()
        }
        if let channel, channel.handshaken { channel.send(message); return }
        pending.append(message)
        if channel == nil { connect() }
    }

    private func connect() {
        guard let target = connectionTarget else { return }
        let connection = NWConnection(to: target, using: endpoint.clientParameters(psk: connectionKey))
        let channel = FlingChannel(connection: connection, queue: endpoint.queue)
        self.channel = channel
        // The receiver speaks first with a nonce; the sender's hello answers it with a proof of its key.
        channel.onReady = {}
        channel.onFrame = { [self] frame in receive(frame) }
        channel.onClose = { [self] reason in closed(reason) }
        channel.start()
    }

    private func receive(_ frame: FlingFrame) {
        guard !finished else { return }
        guard let message = try? FlingWire.decode(frame) else { return abortConnection() }
        guard let channel else { return }
        if !channel.handshaken {
            guard case .hello(let hello) = message, address.id.isEmpty || hello.id == address.id, let nonce = hello.nonce else { return abortConnection() }
            let claimed = endpoint.hooks.spoofHelloID ?? endpoint.identity.id
            channel.send(.hello(FlingHello(id: claimed, name: endpoint.identity.name, model: endpoint.identity.model,
                                           nonce: nil, proof: FlingCrypto.helloProof(psk: connectionKey, nonce: nonce, id: claimed))))
            channel.handshaken = true
            let queued = pending
            pending = []
            for m in queued { channel.send(m) }
            return
        }
        apply(step(.received(message)))
    }

    private func closed(_ reason: FlingCloseReason) {
        guard !finished else { return }
        if let channel, !channel.becameReady, case .failed(let error) = reason, case .tls = error { tlsRejected = true }
        apply(step(.connectionLost))
    }

    private func abortConnection() {
        apply(step(.connectionLost))
        channel?.cancel()
    }

    // MARK: Streaming

    private func stream(_ index: Int) {
        guard let url = urls[index], let handle = try? FileHandle(forReadingFrom: url) else {
            apply(step(.connectionLost)); return
        }
        var firstChunk = true
        func next() {
            if machine.state.isFinal || finished { try? handle.close(); return }
            let data = (try? handle.read(upToCount: FlingLimits.sendChunkBytes)) ?? Data()
            guard !data.isEmpty else {
                try? handle.close()
                apply(step(.fileSent(index: index)))
                return
            }
            var bytes = data
            if firstChunk, endpoint.hooks.corruptByte { bytes[bytes.startIndex] ^= 0xFF }
            firstChunk = false
            guard let channel else { return }
            channel.send(FlingWire.encode(chunk: FlingChunk(index: UInt32(index), bytes: bytes))) { [self] error in
                guard error == nil else { return }
                sentBytes += Int64(data.count)
                _ = step(.progress(sent: sentBytes))
                emitProgress()
                let delay = endpoint.hooks.chunkDelayMs
                if delay > 0 { endpoint.queue.asyncAfter(deadline: .now() + .milliseconds(delay)) { next() } } else { next() }
            }
        }
        next()
    }

    private func emitProgress() {
        let now = Date()
        if now.timeIntervalSince(lastProgress) > 0.1 || sentBytes >= totalBytes {
            lastProgress = now
            endpoint.emit(.progress(stackID: stackID, direction: .send, done: sentBytes, total: totalBytes))
        }
    }

    // MARK: Ending

    private func announceIfFinal() {
        let state = machine.state
        guard state.isFinal, !announced else { return }
        announced = true
        switch state {
        case .done: endpoint.emit(.stackFinished(stackID: stackID, direction: .send))
        case .declined(let reason): endpoint.emit(.declined(stackID: stackID, direction: .send, reason: reason))
        case .cancelled: endpoint.emit(.cancelled(stackID: stackID, direction: .send))
        case .failed(let failure):
            let reason = tlsRejected ? "tlsRejected" : String(describing: failure)
            endpoint.emit(.failed(stackID: stackID, direction: .send, reason: reason))
        default: break
        }
        finished = true
        endpoint.forget(sendStack: stackID)
    }

    func cancel() { apply(step(.userCancel)) }

    func tick(_ now: Date) {
        guard !finished, let channel else { return }
        if case .awaitingAccept = machine.state {
            // The other Mac may be asking its person for up to a minute.
            if let sent = offerSentAt, now.timeIntervalSince(sent) <= FlingLimits.promptTimeout + 5 { channel.lastActivity = now }
        }
        if FlingTimeoutPolicy(connectedAt: channel.connectedAt, lastActivity: channel.lastActivity).shouldClose(now: now, handshaken: channel.handshaken) {
            apply(step(.connectionLost))
            channel.cancel()
        }
    }

    func abort() {
        if !machine.state.isFinal { apply(step(.userCancel)) }
        finished = true
        channel?.cancel()
    }
}
