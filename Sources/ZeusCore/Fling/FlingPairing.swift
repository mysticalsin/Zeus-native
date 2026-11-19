import CryptoKit
import Foundation

public enum FlingPairRole: Equatable, Sendable { case initiator, responder }

public enum FlingPairFailure: Equatable, Sendable {
    case commitmentMismatch, badKey, badConfirm, unexpectedMessage, connectionLost, peerRefused
    /// The other Mac's id already has a key here. Remove it in Settings before pairing again.
    case alreadyPaired, timedOut
}

public enum FlingPairingState: Equatable, Sendable {
    case idle, committing, awaitingKey, awaitingReveal
    case showingCode(code: String, deadline: Date)
    /// The responder accepted and waits for the initiator's own confirmation.
    case awaitingConfirm(deadline: Date)
    case confirmed, declined, expired
    case failed(FlingPairFailure)

    public var isFinal: Bool {
        switch self {
        case .confirmed, .declined, .expired, .failed: return true
        default: return false
        }
    }
}

public enum FlingPairingEvent: Sendable {
    case start(now: Date)
    case received(FlingMessage, now: Date)
    case userAccept, userDecline, userCancel
    case tick(now: Date)
    case connectionLost
}

public enum FlingPairingEffect: Equatable, Sendable {
    case send(FlingMessage)
    /// Emitted only once both sides have confirmed.
    case storePSK(peerID: String, psk: Data)
    case showCode(String, role: FlingPairRole)
    case hidePrompt
    case close
}

/// Pairing as an explicit machine: a commitment first, then the keys, then a short code both people compare.
/// Nothing is stored unless both Macs confirmed.
public struct FlingPairingMachine: Sendable {
    public let role: FlingPairRole
    public private(set) var state: FlingPairingState = .idle
    private let localID: String
    private let remoteID: String
    private let entropy: FlingPairingEntropy
    private var peerCommitment: Data?
    private var peerPublic: Data?
    private var secrets: FlingPairSecrets?
    /// The initiator completes only when the peer confirmed and its own person accepted, in either order.
    private var peerConfirmed = false
    private var userAccepted = false

    public init(role: FlingPairRole, localID: String, remoteID: String, entropy: FlingPairingEntropy) {
        self.role = role; self.localID = localID; self.remoteID = remoteID; self.entropy = entropy
    }

    private var ownPublic: Data { entropy.privateKey.publicKey.rawRepresentation }
    private var ownLabel: String { role == .initiator ? "initiator" : "responder" }
    private var peerLabel: String { role == .initiator ? "responder" : "initiator" }
    private func b64(_ data: Data) -> String { data.base64EncodedString() }

    private mutating func end(_ final: FlingPairingState, send message: FlingMessage? = nil) -> [FlingPairingEffect] {
        state = final
        var effects: [FlingPairingEffect] = []
        if let message { effects.append(.send(message)) }
        effects += [.hidePrompt, .close]
        return effects
    }

    /// The starting Mac's end: its own confirmation goes out first, then the key is stored.
    private mutating func completeIfBothAgree() -> [FlingPairingEffect] {
        guard peerConfirmed, userAccepted, let secrets else { return [] }
        state = .confirmed
        let own = FlingCrypto.confirmMAC(psk: secrets.psk, transcript: secrets.transcript, label: ownLabel)
        return [.send(.pairConfirm(FlingPairConfirm(mac: b64(own)))), .storePSK(peerID: remoteID, psk: secrets.psk), .hidePrompt, .close]
    }

    private mutating func derive() -> Bool {
        guard let peerPublic else { return false }
        let initiator = role == .initiator
        let derived = try? FlingCrypto.secrets(
            ownPrivate: entropy.privateKey, peerPublic: peerPublic,
            initiatorID: initiator ? localID : remoteID, responderID: initiator ? remoteID : localID,
            initiatorPublic: initiator ? ownPublic : peerPublic, responderPublic: initiator ? peerPublic : ownPublic,
            nonce: initiator ? entropy.nonce : (revealedNonce ?? Data()))
        secrets = derived
        return derived != nil
    }
    private var revealedNonce: Data?

    public mutating func handle(_ event: FlingPairingEvent) -> [FlingPairingEffect] {
        if state.isFinal { return [] }
        switch event {
        case .start:
            guard role == .initiator, state == .idle else { return [] }
            state = .awaitingKey
            return [.send(.pairCommit(FlingPairCommit(h: b64(FlingCrypto.commitment(pub: ownPublic, nonce: entropy.nonce)))))]

        case .connectionLost:
            return end(.failed(.connectionLost))

        case .userCancel:
            return end(.declined, send: .pairDecline(FlingPairDecline(reason: "cancelled")))

        case .userDecline:
            guard case .showingCode = state else { return [] }
            return end(.declined, send: .pairDecline(FlingPairDecline(reason: "declined")))

        case .userAccept:
            if role == .initiator {
                guard case .showingCode = state else { return [] }
                userAccepted = true
                return completeIfBothAgree()
            }
            guard role == .responder, case .showingCode(_, let deadline) = state, let secrets else { return [] }
            state = .awaitingConfirm(deadline: deadline)
            let mac = FlingCrypto.confirmMAC(psk: secrets.psk, transcript: secrets.transcript, label: ownLabel)
            return [.send(.pairConfirm(FlingPairConfirm(mac: b64(mac)))), .hidePrompt]

        case .tick(let now):
            switch state {
            case .showingCode(_, let deadline), .awaitingConfirm(let deadline):
                guard now >= deadline else { return [] }
                return end(.expired, send: .pairDecline(FlingPairDecline(reason: "timeout")))
            default: return []
            }

        case .received(let message, let now):
            return receive(message, now: now)
        }
    }

    private mutating func receive(_ message: FlingMessage, now: Date) -> [FlingPairingEffect] {
        if case .pairDecline = message { return end(.declined) }
        switch (role, state, message) {
        case (.responder, .idle, .pairCommit(let commit)):
            guard let h = Data(base64Encoded: commit.h) else { return end(.failed(.unexpectedMessage), send: .pairDecline(FlingPairDecline(reason: "protocol"))) }
            peerCommitment = h
            state = .awaitingReveal
            return [.send(.pairKey(FlingPairKey(pub: b64(ownPublic))))]

        case (.initiator, .awaitingKey, .pairKey(let key)):
            guard let pub = Data(base64Encoded: key.pub) else { return end(.failed(.badKey), send: .pairDecline(FlingPairDecline(reason: "key"))) }
            peerPublic = pub
            guard derive(), let secrets else { return end(.failed(.badKey), send: .pairDecline(FlingPairDecline(reason: "key"))) }
            state = .showingCode(code: secrets.code, deadline: now.addingTimeInterval(FlingLimits.promptTimeout))
            return [.send(.pairReveal(FlingPairReveal(pub: b64(ownPublic), nonce: b64(entropy.nonce)))),
                    .showCode(secrets.code, role: .initiator)]

        case (.responder, .awaitingReveal, .pairReveal(let reveal)):
            guard let pub = Data(base64Encoded: reveal.pub), let nonce = Data(base64Encoded: reveal.nonce),
                  FlingCrypto.commitment(pub: pub, nonce: nonce) == peerCommitment else {
                return end(.failed(.commitmentMismatch), send: .pairDecline(FlingPairDecline(reason: "commitment")))
            }
            peerPublic = pub
            revealedNonce = nonce
            guard derive(), let secrets else { return end(.failed(.badKey), send: .pairDecline(FlingPairDecline(reason: "key"))) }
            state = .showingCode(code: secrets.code, deadline: now.addingTimeInterval(FlingLimits.promptTimeout))
            return [.showCode(secrets.code, role: .responder)]

        case (.initiator, .showingCode, .pairConfirm(let confirm)):
            guard let secrets, let mac = Data(base64Encoded: confirm.mac),
                  FlingCrypto.isValidConfirm(mac, psk: secrets.psk, transcript: secrets.transcript, label: peerLabel) else {
                return end(.failed(.badConfirm), send: .pairDecline(FlingPairDecline(reason: "confirm")))
            }
            peerConfirmed = true
            return completeIfBothAgree()

        case (.responder, .awaitingConfirm, .pairConfirm(let confirm)):
            guard let secrets, let mac = Data(base64Encoded: confirm.mac),
                  FlingCrypto.isValidConfirm(mac, psk: secrets.psk, transcript: secrets.transcript, label: peerLabel) else {
                return end(.failed(.badConfirm), send: .pairDecline(FlingPairDecline(reason: "confirm")))
            }
            state = .confirmed
            return [.storePSK(peerID: remoteID, psk: secrets.psk), .hidePrompt, .close]

        default:
            return end(.failed(.unexpectedMessage), send: .pairDecline(FlingPairDecline(reason: "protocol")))
        }
    }
}

/// Three failed attempts from one id, or from one address under any ids, inside ten minutes mute it for ten minutes.
/// A failure is a decline, an expiry, a dropped connection or a step that never arrived.
public struct FlingMuteLedger: Sendable {
    private var failures: [String: [Date]] = [:]
    private var mutedUntil: [String: Date] = [:]
    public static let window: TimeInterval = 10 * 60
    public static let threshold = 3
    public init() {}

    private mutating func record(_ key: String, now: Date) {
        var recent = (failures[key] ?? []).filter { now.timeIntervalSince($0) <= Self.window }
        recent.append(now)
        if recent.count >= Self.threshold {
            mutedUntil[key] = now.addingTimeInterval(Self.window)
            failures[key] = nil
        } else {
            failures[key] = recent
        }
    }

    public mutating func recordDecline(_ id: String, now: Date) { record("id:" + id, now: now) }

    /// An attempt that never showed a code: it counts against its address only, so an attacker cannot mute a real Mac's id.
    public mutating func recordAddressFailure(_ address: String, now: Date) { record("addr:" + address, now: now) }

    public mutating func recordFailure(_ id: String, address: String, now: Date) {
        record("id:" + id, now: now)
        record("addr:" + address, now: now)
    }

    public func isMuted(_ id: String, now: Date) -> Bool {
        guard let until = mutedUntil["id:" + id] else { return false }
        return now < until
    }

    public func isMuted(_ id: String, address: String, now: Date) -> Bool {
        isMuted(id, now: now) || (mutedUntil["addr:" + address].map { now < $0 } ?? false)
    }
}

/// At most one pairing prompt is on screen at a time.
public struct FlingPairPromptGate: Sendable {
    public private(set) var activeID: String?
    public init() {}
    public mutating func tryBegin(_ id: String) -> Bool {
        guard activeID == nil else { return false }
        activeID = id
        return true
    }
    public mutating func end() { activeID = nil }
}
