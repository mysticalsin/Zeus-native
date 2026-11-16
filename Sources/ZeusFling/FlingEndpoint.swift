import Foundation
import Network
import Security
import UniformTypeIdentifiers
import ZeusCore

public struct FlingIdentity: Sendable, Equatable {
    public var id: String
    public var name: String
    public var model: String
    public init(id: String, name: String, model: String) { self.id = id; self.name = name; self.model = model }
}

public struct FlingPeerAddress: @unchecked Sendable {
    public var id: String
    public var name: String
    public var transfer: NWEndpoint?
    public var pairing: NWEndpoint?
    public init(id: String, name: String, transfer: NWEndpoint?, pairing: NWEndpoint?) { self.id = id; self.name = name; self.transfer = transfer; self.pairing = pairing }

    /// A loopback address for tests and the test helper.
    public static func direct(id: String = "", name: String = "", port: UInt16?, pairPort: UInt16?, host: String = "127.0.0.1") -> FlingPeerAddress {
        func endpoint(_ p: UInt16?) -> NWEndpoint? { p.flatMap { NWEndpoint.Port(rawValue: $0) }.map { .hostPort(host: NWEndpoint.Host(host), port: $0) } }
        return FlingPeerAddress(id: id, name: name, transfer: endpoint(port), pairing: endpoint(pairPort))
    }
}

public struct FlingOutgoingItem: Sendable {
    public enum Content: Sendable { case file(URL), link(String) }
    public var content: Content
    public init(_ content: Content) { self.content = content }
    public static func file(_ url: URL) -> FlingOutgoingItem { .init(.file(url)) }
    public static func link(_ address: String) -> FlingOutgoingItem { .init(.link(address)) }
}

public struct FlingEndpointSettings: Sendable, Equatable {
    public var visibility: FlingVisibility = .everyone
    public var autoAcceptPaired = true
    public var saveMode: FlingSaveMode = .downloads
    /// Whether the app may write into Downloads. When false, arrivals go to the private inbox.
    public var downloadsGranted = true
    /// The name shown to nearby Macs. Empty uses the Mac's own name.
    public var deviceName = ""
    public init() {}
}

public enum FlingDirection: String, Sendable { case send, receive }

public enum FlingEvent: Sendable {
    case listening(port: UInt16?, pairPort: UInt16?)
    case peersChanged([FlingPeerEntry])
    case localNetworkDenied
    case pairCode(code: String, role: FlingPairRole, peerID: String, peerName: String)
    case paired(peerID: String, name: String)
    case pairEnded(FlingPairingState)
    case offer(stackID: UUID, peerID: String, peerName: String, itemCount: Int, totalBytes: Int64)
    case progress(stackID: UUID, direction: FlingDirection, done: Int64, total: Int64)
    case itemArrived(stackID: UUID, index: Int, name: String, url: URL, sha256: String, peerName: String, link: String?)
    case stackFinished(stackID: UUID, direction: FlingDirection)
    case declined(stackID: UUID, direction: FlingDirection, reason: FlingDeclineReason)
    case failed(stackID: UUID?, direction: FlingDirection, reason: String)
    case cancelled(stackID: UUID, direction: FlingDirection)
    case rejected(reason: String, via: String)
}

/// Switches that exist only for the test helper. The default instance does nothing, and the app never builds one.
public final class FlingTestHooks: @unchecked Sendable {
    /// Replaces the first item's name in the offer, after cleaning.
    public var rawName: String?
    /// Pause after every chunk.
    public var chunkDelayMs = 0
    /// Flip one byte of the first chunk after the hash was taken.
    public var corruptByte = false
    /// Connect with a made-up key instead of the stored one.
    public var forceUnknownKey = false
    public var diagnostics: (@Sendable (String) -> Void)?
    public init() {}
}

public enum FlingDiscovery: Sendable {
    /// Bonjour discovery and advertising, with peer-to-peer on.
    case bonjour
    /// Loopback only, no Bonjour. Addresses are passed in by the caller.
    case direct
}

/// What the app needs from a Fling endpoint. The app talks to this, so its tests can use a stand-in with no network.
public protocol FlingTransporting: AnyObject, Sendable {
    var events: AsyncStream<FlingEvent> { get }
    var pairedPeers: [FlingPairedPeer] { get }
    func start()
    func stop()
    func updateSettings(_ settings: FlingEndpointSettings)
    func pair(with address: FlingPeerAddress)
    func answerPairing(accept: Bool)
    func send(_ items: [FlingOutgoingItem], to address: FlingPeerAddress) -> UUID
    func cancel(_ stackID: UUID)
    func answerOffer(_ stackID: UUID, accept: Bool)
    func removePeer(id: String) -> Bool
    func address(of id: String) -> FlingPeerAddress?
}

/// Sends and receives files with other Macs. All state lives on one serial queue; calls from any thread are safe.
public final class FlingEndpoint: FlingTransporting, @unchecked Sendable {
    public static let serviceType = "_zeus-fling._tcp"

    private(set) var identity: FlingIdentity
    private let defaultName: String
    let store: FlingPairingStore
    let saveRoot: URL
    let inbox: URL
    let discovery: FlingDiscovery
    let queue: DispatchQueue
    let hooks: FlingTestHooks
    private let continuation: AsyncStream<FlingEvent>.Continuation
    public let events: AsyncStream<FlingEvent>

    var settings = FlingEndpointSettings()
    var replay = FlingReplayLedger()
    var mute = FlingMuteLedger()
    var promptGate = FlingPairPromptGate()
    var gate = FlingConnectionGate()
    var peers = FlingPeerList()
    var pairSessions: [ObjectIdentifier: FlingPairSession] = [:]
    var receiveSessions: [ObjectIdentifier: FlingReceiveSession] = [:]
    var sendSessions: [UUID: FlingSendSession] = [:]
    var inboundCount = 0

    private var transferListener: NWListener?
    private var pairingListener: NWListener?
    private var browser: NWBrowser?
    private var timer: DispatchSourceTimer?
    private var transferPort: UInt16?
    private var pairingPort: UInt16?
    private var browsed: [String: BrowseEntry] = [:]
    private var lastPeerIDs: [FlingPeerEntry] = []
    private var started = false

    struct BrowseEntry { var name = ""; var model = ""; var transfer: NWEndpoint?; var pairing: NWEndpoint? }

    public init(identity: FlingIdentity, keys: KeychainStore, supportDirectory: URL, saveRoot: URL, inbox: URL,
                discovery: FlingDiscovery, queue: DispatchQueue = DispatchQueue(label: "zeus.fling.endpoint"),
                hooks: FlingTestHooks = FlingTestHooks()) {
        self.identity = identity
        self.defaultName = identity.name
        self.store = FlingPairingStore(keychain: keys, directory: supportDirectory)
        self.saveRoot = saveRoot
        self.inbox = inbox
        self.discovery = discovery
        self.queue = queue
        self.hooks = hooks
        var cont: AsyncStream<FlingEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont
    }

    func emit(_ event: FlingEvent) { continuation.yield(event) }
    func log(_ text: String) { hooks.diagnostics?(text) }

    // MARK: Public API

    public var pairedPeers: [FlingPairedPeer] { store.peers }

    public func start() {
        queue.async { [self] in
            guard !started else { return }
            started = true
            FlingFileSink.sweep(directories: [saveRoot.appendingPathComponent("Fling"), inbox])
            peers.setPaired(store.pairedNames())
            applyListeners()
            if discovery == .bonjour { startBrowser() }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 1, repeating: 1)
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
        }
    }

    public func stop() {
        queue.async { [self] in
            started = false
            timer?.cancel(); timer = nil
            transferListener?.cancel(); transferListener = nil
            pairingListener?.cancel(); pairingListener = nil
            browser?.cancel(); browser = nil
            for s in pairSessions.values { s.abort() }
            for s in receiveSessions.values { s.abort() }
            for s in sendSessions.values { s.abort() }
            pairSessions.removeAll(); receiveSessions.removeAll(); sendSessions.removeAll()
            transferPort = nil; pairingPort = nil
        }
    }

    deinit { continuation.finish() }

    public func updateSettings(_ new: FlingEndpointSettings) {
        queue.async { [self] in
            let trimmed = new.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmed.isEmpty ? defaultName : String(trimmed.prefix(60))
            let listenersChanged = new.visibility != settings.visibility || name != identity.name
            identity.name = name
            settings = new
            if started && listenersChanged { applyListeners() }
        }
    }

    public func pair(with address: FlingPeerAddress) {
        queue.async { [self] in
            guard let endpoint = address.pairing else { emit(.pairEnded(.failed(.connectionLost))); return }
            let session = FlingPairSession(endpoint: self, initiatorTo: endpoint, expectedID: address.id.isEmpty ? nil : address.id)
            pairSessions[ObjectIdentifier(session)] = session
            session.start()
        }
    }

    /// The person's answer to a pairing prompt (accept or decline) or, on the initiating Mac, Cancel.
    public func answerPairing(accept: Bool) {
        queue.async { [self] in
            for session in pairSessions.values { session.answer(accept: accept) }
        }
    }

    /// Every send needs a gesture from the caller. Nothing inside the endpoint calls this.
    @discardableResult
    public func send(_ items: [FlingOutgoingItem], to address: FlingPeerAddress) -> UUID {
        let stackID = UUID()
        queue.async { [self] in
            let session = FlingSendSession(endpoint: self, stackID: stackID, address: address, items: items)
            sendSessions[stackID] = session
            session.start()
        }
        return stackID
    }

    public func cancel(_ stackID: UUID) {
        queue.async { [self] in
            sendSessions[stackID]?.cancel()
            for s in receiveSessions.values where s.stackID == stackID { s.cancel() }
        }
    }

    public func answerOffer(_ stackID: UUID, accept: Bool) {
        queue.async { [self] in
            for s in receiveSessions.values where s.stackID == stackID { s.answer(accept: accept) }
        }
    }

    @discardableResult
    public func removePeer(id: String) -> Bool {
        queue.sync {
            guard store.remove(id: id) else { return false }
            peers.setPaired(store.pairedNames())
            if started { applyTransferListener() }
            return true
        }
    }

    /// The Bonjour address of a nearby Mac, by id.
    public func address(of id: String) -> FlingPeerAddress? {
        queue.sync {
            guard let entry = browsed[id] else { return nil }
            return FlingPeerAddress(id: id, name: entry.name, transfer: entry.transfer, pairing: entry.pairing)
        }
    }

    // MARK: Listeners

    func peerPaired() {
        peers.setPaired(store.pairedNames())
        if started { applyTransferListener() }
    }

    private var loopback: Bool { discovery == .direct }

    private func parameters(psks: [String: Data]?) -> NWParameters {
        let params: NWParameters
        if let psks {
            let tls = NWProtocolTLS.Options()
            let options = tls.securityProtocolOptions
            for (id, key) in psks {
                sec_protocol_options_add_pre_shared_key(options, key.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData,
                                                        Data(id.utf8).withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData)
            }
            sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: 0xCCAC)!)
            sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
            params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        } else {
            params = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        }
        if loopback { params.requiredInterfaceType = .loopback } else { params.includePeerToPeer = true }
        return params
    }

    /// Parameters for an outgoing transfer connection. The identity is our own id; the peer finds the key by it.
    func clientParameters(psk: Data) -> NWParameters { parameters(psks: [identity.id: psk]) }
    func pairingClientParameters() -> NWParameters { parameters(psks: nil) }

    private func serviceName(_ suffix: String) -> String { "Zeus-\(identity.id.prefix(8))\(suffix)" }

    private func txt(_ plan: FlingVisibilityPlan, role: String) -> NWTXTRecord {
        var dictionary = plan.txt
        dictionary["r"] = role
        return NWTXTRecord(dictionary)
    }

    private func plan() -> FlingVisibilityPlan {
        FlingVisibilityPolicy.plan(visibility: settings.visibility, id: identity.id, name: identity.name, model: identity.model, pairPort: 0)
    }

    /// (Re)builds both listeners from the visibility setting and the paired Macs.
    private func applyListeners() {
        applyPairingListener()
        applyTransferListener()
    }

    private func applyPairingListener() {
        pairingListener?.cancel(); pairingListener = nil; pairingPort = nil
        let plan = plan()
        if plan.pairingListener, let listener = try? NWListener(using: parameters(psks: nil), on: .any) {
            if discovery == .bonjour {
                var live = plan
                live.txt["pp"] = "0"
                listener.service = NWListener.Service(name: serviceName("-pair"), type: Self.serviceType, domain: nil, txtRecord: txt(live, role: "p"))
            }
            listener.newConnectionHandler = { [weak self] connection in self?.acceptPairing(connection) }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener, case .ready = state else { return }
                self.pairingPort = listener.port?.rawValue
                self.announceListening()
            }
            pairingListener = listener
            listener.start(queue: queue)
        } else {
            announceListening()
        }
    }

    /// The transfer listener's key list is fixed when it is created, so a pairing or a removal rebuilds it.
    /// With no paired Mac there is nothing to receive from, so there is no transfer listener.
    private func applyTransferListener() {
        transferListener?.cancel(); transferListener = nil; transferPort = nil
        let plan = plan()
        let table = store.pskTable()
        if plan.transferListener, !table.isEmpty, let listener = try? NWListener(using: parameters(psks: table), on: .any) {
            if discovery == .bonjour {
                listener.service = NWListener.Service(name: serviceName(""), type: Self.serviceType, domain: nil, txtRecord: txt(plan, role: "t"))
            }
            listener.newConnectionHandler = { [weak self] connection in self?.acceptTransfer(connection) }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener, case .ready = state else { return }
                self.transferPort = listener.port?.rawValue
                self.announceListening()
            }
            transferListener = listener
            listener.start(queue: queue)
        } else {
            announceListening()
        }
    }

    private func announceListening() {
        let wantsTransfer = transferListener != nil, wantsPairing = pairingListener != nil
        if (wantsTransfer && transferPort == nil) || (wantsPairing && pairingPort == nil) { return }
        emit(.listening(port: transferPort, pairPort: pairingPort))
    }

    // MARK: Inbound

    private func acceptTransfer(_ connection: NWConnection) {
        inboundCount += 1
        let number = inboundCount
        guard gate.admit(connection: number) else { connection.cancel(); return }
        let channel = FlingChannel(connection: connection, queue: queue)
        let session = FlingReceiveSession(endpoint: self, channel: channel, number: number)
        receiveSessions[ObjectIdentifier(session)] = session
        session.start()
    }

    private func acceptPairing(_ connection: NWConnection) {
        inboundCount += 1
        let number = inboundCount
        guard gate.admit(connection: number) else { connection.cancel(); return }
        let session = FlingPairSession(endpoint: self, inbound: connection, number: number)
        pairSessions[ObjectIdentifier(session)] = session
        session.start()
    }

    // MARK: Discovery

    private func startBrowser() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: params)
        browser.stateUpdateHandler = { [weak self] state in
            if case .waiting(let error) = state, case .dns(let code) = error, code == -65570 {
                self?.emit(.localNetworkDenied)
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in self?.browseChanged(results) }
        self.browser = browser
        browser.start(queue: queue)
    }

    private func browseChanged(_ results: Set<NWBrowser.Result>) {
        var next: [String: BrowseEntry] = [:]
        for result in results {
            guard case .bonjour(let record) = result.metadata, let id = record["id"], id != identity.id else { continue }
            var entry = next[id] ?? BrowseEntry()
            if let name = record["name"] { entry.name = name }
            if let model = record["model"] { entry.model = model }
            if entry.name.isEmpty { entry.name = "Mac" }
            if record["r"] == "p" { entry.pairing = result.endpoint } else { entry.transfer = result.endpoint }
            next[id] = entry
        }
        for id in browsed.keys where next[id] == nil { peers.lost(id: id) }
        browsed = next
        markSeen()
    }

    private func markSeen() {
        let now = Date()
        for (id, entry) in browsed { peers.seen(id: id, name: entry.name, model: entry.model, now: now) }
    }

    // MARK: Timer

    private func tick() {
        let now = Date()
        if discovery == .bonjour { markSeen() }
        let visible = peers.visible(now: now)
        if visible != lastPeerIDs { lastPeerIDs = visible; emit(.peersChanged(visible)) }
        for s in pairSessions.values { s.tick(now) }
        for s in receiveSessions.values { s.tick(now) }
        for s in sendSessions.values { s.tick(now) }
    }

    func forget(_ session: FlingPairSession) { pairSessions[ObjectIdentifier(session)] = nil }
    func forget(_ session: FlingReceiveSession) { receiveSessions[ObjectIdentifier(session)] = nil }
    func forget(sendStack id: UUID) { sendSessions[id] = nil }

    func freeBytes() -> Int64 {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: FileManager.default.fileExists(atPath: saveRoot.path) ? saveRoot.path : saveRoot.deletingLastPathComponent().path)
        return (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }
}
