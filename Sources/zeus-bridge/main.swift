import Foundation
import ZeusCore

// Chrome owns stdin/stdout with four-byte length-prefixed JSON frames. The only local app
// surface is ZeusPaths.chromeSocket; no browser, provider or capture API is invoked here.
let requestTimeout: TimeInterval = 60

/// Coordinates a terminal stream failure with the cancelable stdin reader. Socket peers receive
/// a failure reply or a transport EOF, never an indefinitely retained reservation.
final class HostLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var input: NativeMessageInput?
    private var server: UnixSocketServer?

    func attach(input: NativeMessageInput, server: UnixSocketServer) {
        lock.withLock { self.input = input; self.server = server }
    }

    func finish(code: Int32) {
        let resources = lock.withLock { () -> (NativeMessageInput?, UnixSocketServer?)? in
            guard !stopped else { return nil }
            stopped = true
            return (input, server)
        }
        guard let resources else { return }
        resources.0?.stop()
        resources.1?.stop()
        // A failed framed stream cannot be reused. Exit also closes original stdio descriptors;
        // a stalled Chrome reader cannot keep this host's input loop alive after output failure.
        exit(code)
    }
}

final class Relay: @unchecked Sendable {
    private enum ProtocolFailure: Error { case invalidMessage }
    private let lock = NSLock()
    private var stopped = false
    private let pending = BridgePendingReplies()
    private let output: NativeMessageOutput
    private let lifetime: HostLifetime
    // Only the serial input consumer accesses this decoder.
    private var decoder = NativeMessagingFrame.Decoder()

    init(lifetime: HostLifetime) throws {
        self.lifetime = lifetime
        output = try NativeMessageOutput(handle: .standardOutput)
    }

    func consume(_ chunk: Data) throws {
        try decoder.consume(chunk) { [self] in try fromChrome($0) }
    }

    func inputEnded(_ end: NativeMessageInput.End) {
        if end == .eof {
            do {
                try decoder.finish()
                pending.failAll(BridgeError(code: BridgeError.notConnected, message: "Chrome's connection ended"))
                let draining = output.finish { [self] result in
                    switch result {
                    case .success: terminate(code: 0)
                    case .failure: terminate(code: 2)
                    }
                }
                if !draining { terminate(code: 2) }
            } catch { terminate(code: 2) }
        } else { terminate(code: 2) }
    }

    private func terminate(code: Int32) {
        let first = lock.withLock { () -> Bool in
            guard !stopped else { return false }
            stopped = true
            return true
        }
        guard first else { return }
        output.stop()
        pending.failAll(BridgeError(code: BridgeError.notConnected, message: "Chrome's connection ended"))
        lifetime.finish(code: code)
    }

    private func enqueue(_ json: Data) -> NativeMessageOutput.Admission {
        guard let frame = try? NativeMessagingFrame.encode(json) else { return .tooLarge }
        return output.enqueue(frame) { [weak self] result in
            if case .failure = result { self?.terminate(code: 2) }
        }
    }

    /// A request from the app: reserve once, then admit its complete frame before scheduling I/O.
    func forward(_ line: Data, reply: @escaping UnixSocketServer.Reply) {
        guard let request = try? JSONDecoder().decode(BridgeRequest.self, from: line) else {
            reply(Self.encode(.failure("unknown", BridgeError(code: "bad_request", message: "Could not decode request"))))
            return
        }
        guard output.isOpen else {
            reply(Self.encode(.failure(request.id, BridgeError(code: BridgeError.notConnected))))
            return
        }
        if request.type == "bridge.status" {
            reply(Self.encode(.success(request.id, .object(["bridge": .bool(true), "version": .string(ZeusCoreVersion.string)]))))
            return
        }
        guard let token = pending.reserve(id: request.id, reply: reply) else { return }
        switch enqueue(line) {
        case .accepted:
            pending.armTimeout(id: request.id, token: token, after: requestTimeout)
        case .tooLarge:
            pending.complete(.failure(request.id, BridgeError(code: "too_large", message: "Request is over Chrome's 1 MB limit")), token: token)
        case .full:
            pending.complete(.failure(request.id, BridgeError(code: "busy", message: "Chrome's connection is busy. Try again.")), token: token)
        case .closed:
            pending.complete(.failure(request.id, BridgeError(code: BridgeError.notConnected)), token: token)
        }
    }

    /// Valid late responses are ignored. Invalid framed JSON or oversized correlation IDs close
    /// the transport; stdout cannot be used for diagnostic text or a resynchronization guess.
    private func fromChrome(_ message: Data) throws {
        if let response = try? JSONDecoder().decode(BridgeResponse.self, from: message) {
            guard response.id.utf8.count <= 256 else { throw ProtocolFailure.invalidMessage }
            pending.complete(response)
            return
        }
        guard let request = try? JSONDecoder().decode(BridgeRequest.self, from: message),
              request.id.utf8.count <= 256 else { throw ProtocolFailure.invalidMessage }
        let response: BridgeResponse
        switch request.type {
        case "ping":
            response = .success(request.id, .object([
                "pong": .bool(true), "host": .string(ZeusPaths.nativeHostName),
                "version": .string(ZeusCoreVersion.string),
            ]))
        default:
            response = .failure(request.id, BridgeError(code: "unknown_type", message: request.type))
        }
        guard let json = Self.encode(response), enqueue(json) == .accepted else {
            throw ProtocolFailure.invalidMessage
        }
    }

    private static func encode(_ response: BridgeResponse) -> Data? { try? JSONEncoder().encode(response) }
}

let lifetime = HostLifetime()
do {
    let relay = try Relay(lifetime: lifetime)
    let input = try NativeMessageInput(handle: .standardInput)
    let server = UnixSocketServer(path: ZeusPaths.chromeSocket.path) { [relay] line, reply in
        relay.forward(line, reply: reply)
    }
    lifetime.attach(input: input, server: server)
    // Without a socket the extension still connects; the app reports Chrome as unreachable.
    try? server.start()
    input.start(consume: { [relay] in try relay.consume($0) }, ended: { [relay] in relay.inputEnded($0) })
    dispatchMain()
} catch {
    exit(2)
}
