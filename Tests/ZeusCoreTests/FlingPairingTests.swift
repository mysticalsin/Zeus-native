import CryptoKit
import Foundation
import Testing
@testable import ZeusCore

@Suite("Fling pairing")
struct FlingPairingTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func entropy(_ seed: UInt8) -> FlingPairingEntropy {
        let key = try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(repeating: seed, count: 32))
        return FlingPairingEntropy(privateKey: key, nonce: Data(repeating: seed &+ 100, count: 16))
    }

    private func pair() -> (initiator: FlingPairingMachine, responder: FlingPairingMachine) {
        (FlingPairingMachine(role: .initiator, localID: "idA", remoteID: "idB", entropy: entropy(1)),
         FlingPairingMachine(role: .responder, localID: "idB", remoteID: "idA", entropy: entropy(2)))
    }

    /// Delivers every `send` effect to the other machine until neither has anything left to say. `first` are the
    /// effects the originator just produced; the result holds everything each machine produced, `first` included.
    @discardableResult
    private func pump(_ i: inout FlingPairingMachine, _ r: inout FlingPairingMachine, fromInitiator: Bool = true, first: [FlingPairingEffect], now: Date, tamper: ((FlingMessage) -> FlingMessage)? = nil) -> (i: [FlingPairingEffect], r: [FlingPairingEffect]) {
        func messages(_ effects: [FlingPairingEffect]) -> [FlingMessage] {
            effects.compactMap { if case .send(let m) = $0 { return m } else { return nil } }
        }
        var iEffects = fromInitiator ? first : [], rEffects = fromInitiator ? [] : first
        var toResponder = fromInitiator ? messages(first) : []
        var toInitiator = fromInitiator ? [] : messages(first)
        while !toResponder.isEmpty || !toInitiator.isEmpty {
            let forR = toResponder, forI = toInitiator
            toResponder = []; toInitiator = []
            for m in forR {
                let out = r.handle(.received(tamper?(m) ?? m, now: now)); rEffects += out
                toInitiator += messages(out)
            }
            for m in forI {
                let out = i.handle(.received(m, now: now)); iEffects += out
                toResponder += messages(out)
            }
        }
        return (iEffects, rEffects)
    }

    private func shownCode(_ effects: [FlingPairingEffect]) -> String? {
        for case .showCode(let code, _) in effects { return code }
        return nil
    }
    private func stored(_ effects: [FlingPairingEffect]) -> [(String, Data)] {
        effects.compactMap { if case .storePSK(let id, let key) = $0 { return (id, key) } else { return nil } }
    }

    /// REG-663: both Macs derive the same six digit code and the same key, and a different id gives a different code.
    @Test func bothSidesDeriveTheSameCodeAndKey() throws {
        var (i, r) = pair()
        let out = pump(&i, &r, first: i.handle(.start(now: t0)), now: t0)
        let codeI = try #require(shownCode(out.i)), codeR = try #require(shownCode(out.r))
        #expect(codeI == codeR)
        #expect(codeI.count == 6 && codeI.allSatisfy(\.isNumber))

        let a = entropy(1), b = entropy(2)
        let one = try FlingCrypto.secrets(ownPrivate: a.privateKey, peerPublic: b.privateKey.publicKey.rawRepresentation, initiatorID: "idA", responderID: "idB", initiatorPublic: a.privateKey.publicKey.rawRepresentation, responderPublic: b.privateKey.publicKey.rawRepresentation, nonce: a.nonce)
        let two = try FlingCrypto.secrets(ownPrivate: b.privateKey, peerPublic: a.privateKey.publicKey.rawRepresentation, initiatorID: "idA", responderID: "idB", initiatorPublic: a.privateKey.publicKey.rawRepresentation, responderPublic: b.privateKey.publicKey.rawRepresentation, nonce: a.nonce)
        #expect(one.code == two.code && one.psk == two.psk && one.psk.count == 32)
        let other = try FlingCrypto.secrets(ownPrivate: a.privateKey, peerPublic: b.privateKey.publicKey.rawRepresentation, initiatorID: "idA", responderID: "idZ", initiatorPublic: a.privateKey.publicKey.rawRepresentation, responderPublic: b.privateKey.publicKey.rawRepresentation, nonce: a.nonce)
        #expect(other.psk != one.psk)
    }

    @Test func aCodeKeepsItsLeadingZeros() {
        #expect(FlingCrypto.formatCode(from: 42) == "000042")
        #expect(FlingCrypto.formatCode(from: 1_000_007) == "000007")
    }

    /// REG-664: a reveal that does not match the commitment fails the pairing, shows no code, and stores nothing.
    @Test func aRevealThatBreaksTheCommitmentFailsAndStoresNothing() {
        var (i, r) = pair()
        let evil = entropy(9).privateKey.publicKey.rawRepresentation.base64EncodedString()
        let out = pump(&i, &r, first: i.handle(.start(now: t0)), now: t0) { message in
            if case .pairReveal(let reveal) = message { return .pairReveal(FlingPairReveal(pub: evil, nonce: reveal.nonce)) }
            return message
        }
        #expect(r.state == .failed(.commitmentMismatch))
        #expect(shownCode(out.r) == nil)
        #expect(stored(out.r).isEmpty && stored(out.i).isEmpty)
    }

    /// REG-665: the key is stored only when both sides confirm; every other ending stores nothing.
    @Test func theKeyIsStoredOnlyAfterBothConfirm() throws {
        var (i, r) = pair()
        let start = pump(&i, &r, first: i.handle(.start(now: t0)), now: t0)
        #expect(stored(start.i).isEmpty && stored(start.r).isEmpty)
        #expect(i.state == .showingCode(code: try #require(shownCode(start.i)), deadline: t0.addingTimeInterval(60)))
        let accepted = pump(&i, &r, fromInitiator: false, first: r.handle(.userAccept), now: t0)
        #expect(i.state == .confirmed && r.state == .confirmed)
        let si = stored(accepted.i), sr = stored(accepted.r)
        #expect(si.count == 1 && sr.count == 1)
        #expect(si[0].0 == "idB" && sr[0].0 == "idA")
        #expect(si[0].1 == sr[0].1 && si[0].1.count == 32)
        #expect(accepted.i.contains(.close) && accepted.r.contains(.close))
    }

    @Test func declineCancelExpiryAndLossStoreNothing() {
        // Responder declines.
        var (i, r) = pair()
        _ = pump(&i, &r, first: i.handle(.start(now: t0)), now: t0)
        let decline = r.handle(.userDecline)
        #expect(r.state == .declined)
        #expect(stored(decline).isEmpty)
        // The decline message reaches the initiator.
        for case .send(let m) in decline { _ = i.handle(.received(m, now: t0)) }
        #expect(i.state == .declined)

        // Initiator cancels.
        var (i2, r2) = pair()
        _ = pump(&i2, &r2, first: i2.handle(.start(now: t0)), now: t0)
        let cancel = i2.handle(.userCancel)
        #expect(i2.state == .declined && stored(cancel).isEmpty)
        for case .send(let m) in cancel { _ = r2.handle(.received(m, now: t0)) }
        #expect(r2.state == .declined)

        // The code expires after 60 seconds, not before.
        var (i3, r3) = pair()
        _ = pump(&i3, &r3, first: i3.handle(.start(now: t0)), now: t0)
        let out1 = r3.handle(.tick(now: t0.addingTimeInterval(59)))
        #expect(out1.isEmpty)
        let expiry = r3.handle(.tick(now: t0.addingTimeInterval(60)))
        #expect(r3.state == .expired && stored(expiry).isEmpty && expiry.contains(.hidePrompt) && expiry.contains(.close))

        // The connection drops mid-way.
        var (i4, r4) = pair()
        _ = pump(&i4, &r4, first: i4.handle(.start(now: t0)), now: t0)
        _ = i4.handle(.connectionLost)
        #expect(i4.state == .failed(.connectionLost))
    }

    @Test func aFinishedMachineIgnoresLateEvents() {
        var (i, r) = pair()
        _ = pump(&i, &r, first: i.handle(.start(now: t0)), now: t0)
        _ = r.handle(.userDecline)
        let out2 = r.handle(.userAccept)
        #expect(out2.isEmpty)
        #expect(r.state == .declined)
    }

    @Test func aConfirmWithTheWrongMACDoesNotStore() {
        var (i, r) = pair()
        _ = pump(&i, &r, first: i.handle(.start(now: t0)), now: t0)
        let out = i.handle(.received(.pairConfirm(FlingPairConfirm(mac: "AAAA")), now: t0))
        #expect(stored(out).isEmpty)
        #expect(i.state == .failed(.badConfirm))
    }

    /// REG-666: three declines from one id inside ten minutes mute that id for ten minutes, and only one pairing prompt shows at a time.
    @Test func threeDeclinesMuteAnIdAndOnlyOnePromptShows() {
        var ledger = FlingMuteLedger()
        #expect(!ledger.isMuted("idX", now: t0))
        ledger.recordDecline("idX", now: t0)
        ledger.recordDecline("idX", now: t0.addingTimeInterval(60))
        #expect(!ledger.isMuted("idX", now: t0.addingTimeInterval(61)))
        ledger.recordDecline("idX", now: t0.addingTimeInterval(120))
        #expect(ledger.isMuted("idX", now: t0.addingTimeInterval(121)))
        #expect(!ledger.isMuted("idY", now: t0.addingTimeInterval(121)))
        #expect(ledger.isMuted("idX", now: t0.addingTimeInterval(120 + 599)))
        #expect(!ledger.isMuted("idX", now: t0.addingTimeInterval(120 + 601)))

        var slow = FlingMuteLedger()
        slow.recordDecline("idX", now: t0)
        slow.recordDecline("idX", now: t0.addingTimeInterval(400))
        slow.recordDecline("idX", now: t0.addingTimeInterval(700)) // first one is older than 10 min
        #expect(!slow.isMuted("idX", now: t0.addingTimeInterval(701)))

        var gate = FlingPairPromptGate()
        let out3 = gate.tryBegin("idA")
        #expect(out3)
        let out4 = gate.tryBegin("idB")
        #expect(!out4)
        gate.end()
        let out5 = gate.tryBegin("idB")
        #expect(out5)
    }
}
