import Foundation
import Network
import ZeusCore

enum FlingCloseReason {
    case cancelled, eof
    case failed(NWError)
    case protocolError(FlingWireError)
}

/// One NWConnection with frame decoding. Everything runs on the endpoint's serial queue.
final class FlingChannel {
    let connection: NWConnection
    private let queue: DispatchQueue
    private var decoder = FlingFrameDecoder()
    private var finished = false
    private(set) var becameReady = false
    var onReady: (() -> Void)?
    var onFrame: ((FlingFrame) -> Void)?
    var onClose: ((FlingCloseReason) -> Void)?
    let connectedAt = Date()
    var lastActivity = Date()
    var handshaken = false
    /// The identity the peer presented in the TLS pre-shared key exchange, when the system reports it.
    private(set) var tlsIdentity: String?

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.becameReady = true
                self.readTLSIdentity()
                self.onReady?()
                self.receiveLoop()
            case .failed(let error): self.finish(.failed(error))
            case .waiting(let error):
                // A LAN peer that cannot be reached, or a handshake the other side refused: do not wait.
                self.connection.cancel()
                self.finish(.failed(error))
            case .cancelled: self.finish(.cancelled)
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func readTLSIdentity() {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { return }
        sec_protocol_metadata_access_pre_shared_keys(metadata.securityProtocolMetadata) { [weak self] _, identity in
            let bytes = Data(identity as DispatchData)
            self?.tlsIdentity = String(decoding: bytes, as: UTF8.self)
        }
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.finished else { return }
            if let data, !data.isEmpty {
                self.lastActivity = Date()
                do {
                    for frame in try self.decoder.feed(data) { self.onFrame?(frame); if self.finished { return } }
                } catch {
                    self.finish(.protocolError(error as? FlingWireError ?? .malformed))
                    self.connection.cancel()
                    return
                }
            }
            if let error { self.finish(.failed(error)); return }
            if isComplete { self.finish(.eof); self.connection.cancel(); return }
            self.receiveLoop()
        }
    }

    func send(_ data: Data, completion: ((NWError?) -> Void)? = nil) {
        guard !finished else { return }
        lastActivity = Date()
        connection.send(content: data, completion: .contentProcessed { error in completion?(error) })
    }

    func send(_ message: FlingMessage) {
        guard let data = try? FlingWire.encode(message) else { return }
        send(data)
    }

    /// Lets queued frames go out, then closes.
    func closeAfterFlush() {
        guard !finished else { return }
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
    }

    func cancel() { connection.cancel() }

    private func finish(_ reason: FlingCloseReason) {
        guard !finished else { return }
        finished = true
        let handler = onClose
        onReady = nil; onFrame = nil; onClose = nil
        handler?(reason)
    }
}
