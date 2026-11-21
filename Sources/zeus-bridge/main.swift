import Foundation
import ZeusCore

// Chrome owns stdin/stdout with four-byte length-prefixed JSON frames. The only local app
// surface is ZeusPaths.chromeSocket; no browser, provider or capture API is invoked here.
let requestTimeout: TimeInterval = 60

final class Relay: @unchecked Sendable {
    private enum ProtocolFailure: Error { case invalidMessage }
    private let lock = NSLock()
    private var stopped = false
    private var identityReady = false
    private let pending = BridgePendingReplies()
    private let output: NativeMessageOutput
    private let lifetime: BridgeHostLifetime
    // Only the serial input consumer accesses this decoder.
    private var decoder = NativeMessagingFrame.Decoder()

    init(lifetime: BridgeHostLifetime) throws {
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
        lifetime.finish()
        // A failed framed stream cannot be reused. Exit also closes original stdio descriptors.
        exit(code)
    }

    func noteIdentityReady() {
        lock.withLock { identityReady = true }
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
        let ready = lock.withLock { identityReady }
        switch BridgeChromeAdmission.action(for: message, identityReady: ready) {
        case .reply(let response):
            guard let json = Self.encode(response), enqueue(json) == .accepted else {
                throw ProtocolFailure.invalidMessage
            }
        case .completePending(let response):
            pending.complete(response)
        case .close:
            throw ProtocolFailure.invalidMessage
        }
    }

    private static func encode(_ response: BridgeResponse) -> Data? { try? JSONEncoder().encode(response) }
}

let lifetime = BridgeHostLifetime()
do {
    let relay = try Relay(lifetime: lifetime)
    let input = try NativeMessageInput(handle: .standardInput)
    let server = UnixSocketServer(path: ZeusPaths.chromeSocket.path, peerPolicy: ChromeSocketPeers.policy(environment: ProcessInfo.processInfo.environment),
                                  peerVerifier: ChromeSocketPeers.verifier) { [relay] line, reply in
        relay.forward(line, reply: reply)
    }
    // Attach before the reader starts, so EOF or a bad frame can stop the socket instead of
    // exiting with the file still on disk. drive is the only startup order.
    lifetime.attach(input: input, server: server)
    BridgeHostStartup.drive { step in
        switch step {
        case .bindSocket:
            try? server.start()
        case .armStdin:
            // Arm stdin before the signature read. That call can block the main thread, and
            // Chrome's frame is larger than the pipe.
            input.start(consume: { [relay] in try relay.consume($0) }, ended: { [relay] in relay.inputEnded($0) })
        case .captureIdentity:
            // Chrome keeps this process running while the app is rebuilt and replaces the installed file.
            // Read the identity now, before that happens, so a later peer is still recognised.
            PeerSigning.captureOwnIdentity()
        case .markIdentityReady:
            relay.noteIdentityReady()
        }
    }
    dispatchMain()
} catch {
    lifetime.finish()
    exit(2)
}
