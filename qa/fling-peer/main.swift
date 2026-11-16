// zeus-fling-peer: a test-only executable. It runs one FlingEndpoint and takes JSON-line commands on stdin and
// prints JSON-line events on stdout, so a test can run two or three real processes against each other.
// It uses an in-memory Keychain and a temporary save root, and it is never bundled into the app.
import Foundation
import Network
import ZeusCore
import ZeusFling

func argument(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

guard let name = argument("--name"), let root = argument("--root") else {
    FileHandle.standardError.write(Data("usage: zeus-fling-peer --name <name> --root <dir> [--id <id>]\n".utf8))
    exit(2)
}
let id = argument("--id") ?? UUID().uuidString
let rootURL = URL(fileURLWithPath: root, isDirectory: true)
let suite = "zeus.fling-peer.\(UUID().uuidString)"
let keys = KeychainStore(backend: MemoryKeychain(), defaults: UserDefaults(suiteName: suite)!)
let hooks = FlingTestHooks()
let outputLock = NSLock()

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
    outputLock.lock(); defer { outputLock.unlock() }
    FileHandle.standardOutput.write(data + Data([0x0A]))
}

hooks.diagnostics = { text in emit(["event": "diag", "text": text]) }

let endpoint = FlingEndpoint(identity: FlingIdentity(id: id, name: name, model: "Mac-test"), keys: keys,
                             supportDirectory: rootURL.appendingPathComponent("Support"), saveRoot: rootURL,
                             inbox: rootURL.appendingPathComponent("Inbox"), discovery: .direct, hooks: hooks)
let shelf = FlingShelfPersistence(url: rootURL.appendingPathComponent("Shelf/shelf.json"))
var shelfRecords: [FlingShelfRecord] = shelf.load().records

func describe(_ state: FlingPairingState) -> String {
    switch state {
    case .declined: return "declined"
    case .expired: return "expired"
    case .failed(let why): return "failed(\(why))"
    default: return "\(state)"
    }
}

Task {
    for await event in endpoint.events {
        switch event {
        case .listening(let port, let pairPort): emit(["event": "listening", "id": id, "port": Int(port ?? 0), "pairPort": Int(pairPort ?? 0)])
        case .peersChanged(let list): emit(["event": "peers", "count": list.count])
        case .localNetworkDenied: emit(["event": "localNetworkDenied"])
        case .pairCode(let code, let role, let peerID, let peerName): emit(["event": "pairCode", "code": code, "role": "\(role)", "peerID": peerID, "peerName": peerName])
        case .paired(let peerID, let peerName): emit(["event": "paired", "peerID": peerID, "name": peerName])
        case .pairEnded(let state): emit(["event": "pairEnded", "state": describe(state)])
        case .offer(let stackID, let peerID, let peerName, let count, let bytes):
            emit(["event": "offer", "stackID": stackID.uuidString, "peerID": peerID, "peerName": peerName, "items": count, "bytes": bytes])
        case .progress(let stackID, let direction, let done, let total):
            emit(["event": "progress", "stackID": stackID.uuidString, "dir": direction.rawValue, "done": done, "total": total])
        case .itemArrived(let stackID, let index, let itemName, let url, let sha, let peerName, let link):
            shelfRecords.append(FlingShelfRecord(path: url.path, origin: .fling(peer: peerName), stackID: stackID, verified: true, addedAt: Date(), link: link))
            _ = shelf.save(shelfRecords)
            emit(["event": "itemVerified", "stackID": stackID.uuidString, "index": index, "name": itemName, "path": url.path, "sha256": sha])
        case .stackFinished(let stackID, let direction):
            emit(["event": direction == .send ? "sendDone" : "stackDone", "stackID": stackID.uuidString])
        case .declined(let stackID, let direction, let reason):
            emit(["event": "declined", "stackID": stackID.uuidString, "dir": direction.rawValue, "reason": reason.rawValue])
        case .failed(let stackID, let direction, let reason):
            emit(["event": "failed", "stackID": stackID?.uuidString ?? "", "dir": direction.rawValue, "reason": reason])
        case .cancelled(let stackID, let direction):
            emit(["event": "cancelled", "stackID": stackID.uuidString, "dir": direction.rawValue])
        case .rejected(let reason, let via): emit(["event": "rejected", "reason": reason, "via": via])
        }
    }
}

/// Sends hello and an offer to a pairing port and reports what comes back.
func probe(host: String, pairPort: UInt16) {
    let params = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
    params.requiredInterfaceType = .loopback
    let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: pairPort)!, using: params)
    let queue = DispatchQueue(label: "probe")
    var decoder = FlingFrameDecoder()
    var reported = false
    func report(_ reason: String) { if !reported { reported = true; emit(["event": "probeResult", "reason": reason]); connection.cancel() } }
    func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, complete, error in
            if let data, let frames = try? decoder.feed(data) {
                for frame in frames {
                    if let message = try? FlingWire.decode(frame), case .decline(let d) = message { report(d.reason.rawValue) }
                }
            }
            if error != nil || complete { report("closed"); return }
            receive()
        }
    }
    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            let hello = try! FlingWire.encode(.hello(FlingHello(id: id, name: name, model: "Mac-test")))
            let offer = try! FlingWire.encode(.offer(FlingOffer(stackID: UUID(), items: [
                FlingOfferItem(index: 0, name: "x.bin", size: 1, kind: .file, uti: nil, sha256: String(repeating: "0", count: 64), url: nil)])))
            connection.send(content: hello + offer, completion: .contentProcessed { _ in })
            receive()
        case .failed, .waiting: report("unreachable")
        default: break
        }
    }
    connection.start(queue: queue)
}

func items(from list: [[String: Any]]) -> [FlingOutgoingItem] {
    list.compactMap { entry in
        if let path = entry["path"] as? String { return .file(URL(fileURLWithPath: path)) }
        if let link = entry["link"] as? String { return .link(link) }
        return nil
    }
}

endpoint.start()

while let line = readLine() {
    guard let data = line.data(using: .utf8), let command = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let name = command["cmd"] as? String else { continue }
    let host = command["host"] as? String ?? "127.0.0.1"
    switch name {
    case "pair":
        endpoint.pair(with: .direct(port: nil, pairPort: UInt16(command["pairPort"] as? Int ?? 0), host: host))
    case "answerPairing":
        endpoint.answerPairing(accept: command["accept"] as? Bool ?? false, peerID: command["peerID"] as? String)
    case "send":
        let peerID = command["peerID"] as? String ?? endpoint.pairedPeers.first?.id ?? ""
        hooks.rawName = command["rawName"] as? String
        hooks.chunkDelayMs = command["chunkDelayMs"] as? Int ?? 0
        hooks.corruptByte = command["corruptByte"] as? Bool ?? false
        hooks.forceUnknownKey = command["forceUnknownKey"] as? Bool ?? false
        hooks.spoofHelloID = command["spoofID"] as? String
        let address = FlingPeerAddress.direct(id: peerID, port: UInt16(command["port"] as? Int ?? 0), pairPort: nil, host: host)
        let stackID = endpoint.send(items(from: command["items"] as? [[String: Any]] ?? []), to: address)
        emit(["event": "sending", "stackID": stackID.uuidString])
    case "cancel":
        if let text = command["stackID"] as? String, let id = UUID(uuidString: text) { endpoint.cancel(id) }
    case "answerOffer":
        if let text = command["stackID"] as? String, let id = UUID(uuidString: text) { endpoint.answerOffer(id, accept: command["accept"] as? Bool ?? false) }
    case "probe":
        probe(host: host, pairPort: UInt16(command["pairPort"] as? Int ?? 0))
    case "quit":
        endpoint.stop()
        UserDefaults.standard.removePersistentDomain(forName: suite)
        exit(0)
    default:
        break
    }
}
endpoint.stop()
exit(0)
