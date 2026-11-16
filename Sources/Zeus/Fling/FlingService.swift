import AppKit
import Foundation
import Observation
import ZeusCore
import ZeusFling

/// What made a send happen. Every send needs one, so nothing sends on a timer, an arrival, a retry or a reconnect.
enum FlingGesture: String, Sendable { case button, drop, flick, menu }

enum FlingTarget: Equatable, Sendable {
    case peer(id: String)
    case airDrop
}

struct FlingNearbyPeer: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var model: String
    var paired: Bool
}

struct FlingPairingPrompt: Equatable, Sendable {
    var code: String
    var peerID: String
    var peerName: String
    var role: FlingPairRole
}

struct FlingOfferPrompt: Equatable, Sendable {
    var stackID: UUID
    var peerName: String
    var itemCount: Int
    var totalBytes: Int64
}

/// One transfer in flight, for the progress ring.
struct FlingActivity: Equatable, Sendable {
    var stackID: UUID
    var direction: FlingDirection
    var peerID: String
    var peerName: String
    var fraction: Double
}

/// What the Shelf needs from Fling. The journey tests stand in a recording fake for it.
@MainActor
protocol FlingSending: AnyObject {
    var isEnabled: Bool { get }
    var localNetworkDenied: Bool { get }
    var nearby: [FlingNearbyPeer] { get }
    var pairingPrompt: FlingPairingPrompt? { get }
    var pendingOffer: FlingOfferPrompt? { get }
    var activity: [FlingActivity] { get }
    /// Macs that just received a stack from this one; the avatar shows a check for two seconds.
    var justSent: Set<String> { get }
    var lastProblem: String? { get }
    var flickSensitivity: FlickSensitivity { get }
    func turnOn()
    func send(_ items: [TopBarModel.ShelfItem], to target: FlingTarget, gesture: FlingGesture)
    func pair(with peerID: String)
    func answerPairing(accept: Bool)
    func answerOffer(accept: Bool)
    func cancelAll()
}

extension FlingSending {
    var flickSensitivity: FlickSensitivity { .normal }
}

/// The app's side of Fling: it turns the endpoint on and off from Settings, shows what it reports on the Shelf and
/// the notch, and sends only when a caller passes a gesture.
@MainActor @Observable
final class FlingService: FlingSending {
    private(set) var isEnabled = false
    private(set) var localNetworkDenied = false
    private(set) var nearby: [FlingNearbyPeer] = []
    private(set) var pairingPrompt: FlingPairingPrompt?
    private(set) var pendingOffer: FlingOfferPrompt?
    private(set) var activity: [FlingActivity] = []
    private(set) var justSent: Set<String> = []
    private(set) var lastProblem: String?
    private(set) var eventsAreFlowing = false
    private(set) var pairedMacs: [FlingPairedPeer] = []
    /// The service the Settings page reads. Set once the app built it.
    static weak var current: FlingService?
    static let localNetworkSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!

    @ObservationIgnored private let transport: FlingTransporting
    @ObservationIgnored private let model: TopBarModel
    @ObservationIgnored private let setting: @MainActor (String) -> String
    @ObservationIgnored private let downloadsGranted: @MainActor () -> Bool
    /// Opens a received link. A test replaces it; the app opens it in the browser.
    @ObservationIgnored var openLink: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Puts arrived files on the pasteboard in Clipboard mode.
    /// Shows arrivals as floating papers when `fling.papers` is on. The app wires the paper controller in.
    @ObservationIgnored var presentPapers: ([URL], String) -> Void = { _, _ in }
    @ObservationIgnored var writeClipboard: ([URL]) -> Void = { urls in
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
    }
    /// Whether the notch is open; only read when "Receive while the notch is closed" is off.
    @ObservationIgnored var notchIsOpen: @MainActor () -> Bool = { true }
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var applied: Applied?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var arrivals: [UUID: (peer: String, urls: [URL], links: [String])] = [:]
    @ObservationIgnored private var chosenModes: [UUID: FlingSaveMode] = [:]
    @ObservationIgnored private var sends: [UUID: (count: Int, peer: String, peerID: String)] = [:]
    @ObservationIgnored private var observing = false

    private struct Applied: Equatable {
        var enabled: Bool
        var settings: FlingEndpointSettings
    }

    init(model: TopBarModel, transport: FlingTransporting,
         setting: @escaping @MainActor (String) -> String = { SettingsStore.shared.string($0) },
         downloadsGranted: @escaping @MainActor () -> Bool = { FolderAccess.status(for: .downloads) == .granted }) {
        self.model = model
        self.transport = transport
        self.setting = setting
        self.downloadsGranted = downloadsGranted
        pairedMacs = transport.pairedPeers
        startLoop()
    }

    // MARK: Settings

    private func flag(_ id: String) -> Bool { setting(id) == "true" }

    private func currentSettings() -> FlingEndpointSettings {
        var s = FlingEndpointSettings()
        switch setting("fling.visibility") {
        case "Paired only": s.visibility = .pairedOnly
        case "Off": s.visibility = .off
        default: s.visibility = .everyone
        }
        if !flag("fling.receiveInBackground") && !notchIsOpen() { s.visibility = .off }
        s.autoAcceptPaired = flag("fling.autoAcceptPaired")
        switch setting("fling.saveMode") {
        case "Clipboard": s.saveMode = .clipboard
        case "Ask each time": s.saveMode = .ask
        default: s.saveMode = .downloads
        }
        s.downloadsGranted = downloadsGranted()
        s.deviceName = setting("fling.deviceName")
        return s
    }

    /// Applies the Settings switches. Nothing listens or advertises until `fling.enabled` is on.
    func reconfigure() {
        let enabled = flag("fling.enabled")
        let next = Applied(enabled: enabled, settings: currentSettings())
        guard next != applied else { return }
        let was = applied
        applied = next
        if enabled {
            transport.updateSettings(next.settings)
            if !started || was?.enabled != true { transport.start(); started = true }
            isEnabled = true
        } else {
            if started { transport.stop(); started = false }
            isEnabled = false
            nearby = []
            pairingPrompt = nil
            pendingOffer = nil
        }
    }

    /// Re-applies the Settings whenever one changes (the Observation framework re-arms itself).
    func observeSettings() {
        guard !observing else { return }
        observing = true
        track()
    }

    private func track() {
        withObservationTracking {
            reconfigure()
        } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
    }

    /// The Shelf's "Turn on" button. This is the explicit opt-in.
    func turnOn() {
        SettingsStore.shared.set("fling.enabled", "true")
        reconfigure()
    }

    // MARK: What the Settings rows decide

    var flickSensitivity: FlickSensitivity {
        switch setting("fling.flickSensitivity") {
        case "Low": .low
        case "High": .high
        default: .normal
        }
    }
    var opensLinks: Bool { flag("fling.openLinks") }
    var showsPapers: Bool { flag("fling.papers") }

    // MARK: Gestures

    func send(_ items: [TopBarModel.ShelfItem], to target: FlingTarget, gesture: FlingGesture) {
        guard !items.isEmpty else { return }
        switch target {
        case .airDrop:
            NSSharingService(named: .sendViaAirDrop)?.perform(withItems: items.map(\.url))
        case .peer(let id):
            guard let address = transport.address(of: id) else {
                problem("That Mac is not in range. Try again when it shows in Nearby.")
                return
            }
            let name = nearby.first { $0.id == id }?.name ?? address.name
            let total = items.reduce(Int64(0)) { $0 + Self.fileSize($1.url) }
            if FlingLimits.shouldWarn(totalBytes: total) { model.show(.flingProblem(Self.largeSendWarning(total))) }
            let stack = transport.send(items.map { .file($0.url) }, to: address)
            sends[stack] = (items.count, name, id)
            lastProblem = nil
        }
    }

    /// Said before a send over 2 GB. The send still goes: the person asked for it.
    static func largeSendWarning(_ bytes: Int64) -> String {
        "Large send: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)). It can take a while."
    }

    private static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    func pair(with peerID: String) {
        guard let address = transport.address(of: peerID) else {
            problem("That Mac is not in range. Try again when it shows in Nearby.")
            return
        }
        transport.pair(with: address)
    }

    func answerPairing(accept: Bool) {
        transport.answerPairing(accept: accept)
        if !accept { pairingPrompt = nil }
    }

    func answerOffer(accept: Bool) { answerOffer(accept: accept, saveMode: nil) }

    /// In Ask each time mode the person picks where the files go along with the answer.
    func answerOffer(accept: Bool, saveMode: FlingSaveMode?) {
        guard let offer = pendingOffer else { return }
        if accept, let saveMode { chosenModes[offer.stackID] = saveMode }
        transport.answerOffer(offer.stackID, accept: accept, saveMode: saveMode)
        pendingOffer = nil
    }

    /// True when every offer asks where to put the files.
    var asksWhere: Bool { setting("fling.saveMode") == "Ask each time" }
    private var settingSaveMode: FlingSaveMode {
        switch setting("fling.saveMode") {
        case "Clipboard": .clipboard
        case "Ask each time": .ask
        default: .downloads
        }
    }

    func cancelAll() {
        for a in activity { transport.cancel(a.stackID) }
    }

    func removePairedMac(id: String) -> Bool {
        let ok = transport.removePeer(id: id)
        pairedMacs = transport.pairedPeers
        return ok
    }

    private func problem(_ text: String) {
        lastProblem = text
        model.show(.flingProblem(text))
    }

    // MARK: Events

    private func startLoop() {
        let events = transport.events
        loop = Task { [weak self] in
            self?.eventsAreFlowing = true
            for await event in events { self?.handle(event) }
        }
    }

    /// Puts the verified files on the Shelf. When the whole stack finished it also copies them (Clipboard mode) and
    /// opens received web links; a stack that stopped halfway only keeps what already matched.
    private func flush(_ stack: UUID, finished: Bool = false) {
        let mode = chosenModes.removeValue(forKey: stack) ?? settingSaveMode
        guard let pending = arrivals.removeValue(forKey: stack), !pending.urls.isEmpty else { return }
        model.addToShelf(pending.urls, origin: .fling(peer: pending.peer), stack: stack)
        if showsPapers { presentPapers(pending.urls, pending.peer) }
        guard finished else { return }
        if mode == .clipboard { writeClipboard(pending.urls) }
        if opensLinks {
            for text in pending.links where FlingOfferRules.isWebLink(text) {
                if let url = URL(string: text) { openLink(url) }
            }
        }
    }

    private func finish(_ stack: UUID) { activity.removeAll { $0.stackID == stack } }

    func handle(_ event: FlingEvent) {
        switch event {
        case .listening: break
        case .peersChanged(let list):
            nearby = list.map { FlingNearbyPeer(id: $0.id, name: $0.name, model: $0.model, paired: $0.paired) }
        case .localNetworkDenied:
            localNetworkDenied = true
        case .pairCode(let code, let role, let peerID, let peerName):
            pairingPrompt = FlingPairingPrompt(code: code, peerID: peerID, peerName: peerName, role: role)
        case .paired:
            pairingPrompt = nil
            pairedMacs = transport.pairedPeers
        case .pairEnded(let state):
            pairingPrompt = nil
            if case .failed = state { problem("Pairing did not finish. Try again.") }
        case .offer(let stack, _, let name, let count, let bytes):
            pendingOffer = FlingOfferPrompt(stackID: stack, peerName: name, itemCount: count, totalBytes: bytes)
        case .progress(let stack, let direction, let done, let total):
            let fraction = total > 0 ? min(1, Double(done) / Double(total)) : 1
            let name = sends[stack]?.peer ?? arrivals[stack]?.peer ?? ""
            let peerID = sends[stack]?.peerID ?? ""
            if let i = activity.firstIndex(where: { $0.stackID == stack }) { activity[i].fraction = fraction }
            else { activity.append(FlingActivity(stackID: stack, direction: direction, peerID: peerID, peerName: name, fraction: fraction)) }
        case .itemArrived(let stack, _, _, let url, _, let peer, let link):
            arrivals[stack, default: (peer, [], [])].urls.append(url)
            if let link { arrivals[stack]?.links.append(link) }
        case .stackFinished(let stack, let direction):
            finish(stack)
            switch direction {
            case .receive: flush(stack, finished: true)
            case .send:
                if let sent = sends.removeValue(forKey: stack) {
                    model.show(.flingSent(count: sent.count, to: sent.peer))
                    justSent.insert(sent.peerID)
                    let id = sent.peerID
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        self?.justSent.remove(id)
                    }
                }
            }
        case .declined(let stack, let direction, let reason):
            finish(stack); flush(stack); pendingOffer = pendingOffer?.stackID == stack ? nil : pendingOffer
            if direction == .send { sends[stack] = nil; problem(Self.words(for: reason)) }
        case .failed(let stack, let direction, let reason):
            if let stack { finish(stack); flush(stack); if pendingOffer?.stackID == stack { pendingOffer = nil } }
            if direction == .send {
                if let stack { sends[stack] = nil }
                problem(reason == "notPaired" ? "Pair with that Mac first." : "Could not send. Tap to try again.")
            } else if reason == "hashMismatch" {
                problem("Could not verify a file from the other Mac. It was not kept.")
            }
        case .cancelled(let stack, _):
            finish(stack); flush(stack); sends[stack] = nil
            if pendingOffer?.stackID == stack { pendingOffer = nil }
        case .rejected: break
        }
    }

    static func words(for reason: FlingDeclineReason) -> String {
        switch reason {
        case .declined, .timeout: "The other Mac did not accept."
        case .diskFull: "The other Mac does not have room."
        case .badName: "The other Mac could not accept a file name."
        case .tooMany: "Too many items. Send up to 100 at a time."
        case .notPaired: "Pair with that Mac first."
        case .busy: "The other Mac is busy. Try again in a moment."
        default: "The other Mac could not accept that."
        }
    }
}

// MARK: The real endpoint

extension FlingService {
    /// Where Fling keeps its non-secret files: paired Mac names, the private inbox and the Shelf record.
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Zeus", isDirectory: true)
    }

    static var installID: String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "fling.installID") { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: "fling.installID")
        return id
    }

    static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }

    /// The endpoint for this Mac. Building it starts nothing: it listens only after `fling.enabled` is turned on.
    static func liveEndpoint() -> FlingEndpoint {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let name = Host.current().localizedName ?? "Mac"
        return FlingEndpoint(
            identity: FlingIdentity(id: installID, name: name, model: hardwareModel()),
            keys: Keychain.store,
            supportDirectory: supportDirectory.appendingPathComponent("Fling", isDirectory: true),
            saveRoot: downloads,
            inbox: supportDirectory.appendingPathComponent("Fling/Inbox", isDirectory: true),
            discovery: .bonjour)
    }
}
