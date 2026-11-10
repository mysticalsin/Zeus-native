import Foundation
import ZeusCore

// zeus-bridge: Chrome native-messaging host (registered as com.zeus.bridge).
// Chrome starts it when the ZEUS extension calls chrome.runtime.connectNative and talks to it
// over stdin/stdout with length-prefixed JSON frames.
//
// While it runs it serves ~/Library/Application Support/Zeus/chrome.sock. The app sends one
// BridgeRequest per connection there; the bridge forwards it to the extension and writes the
// matching BridgeResponse back. "ping" is answered here so the extension can confirm the link.

/// Longest any extension command may take (opening an AI site and waiting for its message box
/// is the slowest). The app applies its own, usually shorter, timeout per request.
let requestTimeout: TimeInterval = 60

final class Relay: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [String: UnixSocketServer.Reply] = [:]
    private let output = FileHandle.standardOutput

    func toChrome(_ json: Data) -> Bool {
        guard let frame = try? NativeMessagingFrame.encode(json) else { return false }
        lock.withLock { output.write(frame) }
        return true
    }

    func send(_ response: BridgeResponse) {
        if let json = try? JSONEncoder().encode(response) { _ = toChrome(json) }
    }

    /// A request from the app: remember who asked, then pass it to the extension.
    func forward(_ line: Data, reply: @escaping UnixSocketServer.Reply) {
        guard let request = try? JSONDecoder().decode(BridgeRequest.self, from: line) else {
            reply(Self.encode(.failure("unknown", BridgeError(code: "bad_request", message: "Could not decode request"))))
            return
        }
        if request.type == "bridge.status" {
            reply(Self.encode(.success(request.id, .object(["bridge": .bool(true), "version": .string(ZeusCoreVersion.string)]))))
            return
        }
        lock.withLock { pending[request.id] = reply }
        guard toChrome(line) else {
            complete(.failure(request.id, BridgeError(code: "too_large", message: "Request is over Chrome's 1 MB limit")))
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + requestTimeout) { [weak self] in
            self?.complete(.failure(request.id, BridgeError(code: "timeout", message: "Chrome did not answer in time")))
        }
    }

    /// A message from the extension: either an answer for the app, or a request for the bridge.
    func fromChrome(_ message: Data) {
        if let response = try? JSONDecoder().decode(BridgeResponse.self, from: message),
           lock.withLock({ pending[response.id] != nil }) {
            complete(response)
            return
        }
        guard let request = try? JSONDecoder().decode(BridgeRequest.self, from: message) else { return }
        switch request.type {
        case "ping":
            send(.success(request.id, .object([
                "pong": .bool(true),
                "host": .string(ZeusPaths.nativeHostName),
                "version": .string(ZeusCoreVersion.string),
            ])))
        default:
            send(.failure(request.id, BridgeError(code: "unknown_type", message: request.type)))
        }
    }

    private func complete(_ response: BridgeResponse) {
        guard let reply = lock.withLock({ pending.removeValue(forKey: response.id) }) else { return }
        reply(Self.encode(response))
    }

    private static func encode(_ response: BridgeResponse) -> Data? {
        try? JSONEncoder().encode(response)
    }
}

let relay = Relay()
let server = UnixSocketServer(path: ZeusPaths.chromeSocket.path) { line, reply in
    relay.forward(line, reply: reply)
}
// Without the socket the extension still connects; the app just reports Chrome as unreachable.
try? server.start()

var buffer = Data()
let input = FileHandle.standardInput
while true {
    let chunk = input.availableData
    if chunk.isEmpty { break } // Chrome closed the port
    buffer.append(chunk)
    for message in NativeMessagingFrame.decode(&buffer) {
        relay.fromChrome(message)
    }
}
server.stop()
