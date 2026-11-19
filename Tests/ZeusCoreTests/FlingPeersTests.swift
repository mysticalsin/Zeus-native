import Foundation
import Testing
@testable import ZeusCore

@Suite("Fling peers, caps and visibility")
struct FlingPeersTests {
    private let t0 = Date(timeIntervalSince1970: 3_000_000)

    /// REG-676: a peer is listed for ten seconds after it was last seen, paired first then by name, under the name stored at pairing.
    @Test func peersAreFreshForTenSecondsAndPairedFirst() {
        var list = FlingPeerList()
        list.seen(id: "c", name: "Zed", model: "Mac14,2", now: t0)
        list.seen(id: "a", name: "alpha", model: "Mac15,3", now: t0)
        list.seen(id: "b", name: "Beta", model: "Mac15,6", now: t0)
        list.setPaired(["c": "Zed (paired name)"])
        #expect(list.visible(now: t0).map(\.id) == ["c", "a", "b"])
        #expect(list.visible(now: t0).first?.name == "Zed (paired name)")
        #expect(list.visible(now: t0).first?.paired == true)
        #expect(list.visible(now: t0.addingTimeInterval(10)).count == 3)
        #expect(list.visible(now: t0.addingTimeInterval(10.1)).isEmpty)
        list.seen(id: "a", name: "alpha", model: "Mac15,3", now: t0.addingTimeInterval(9))
        #expect(list.visible(now: t0.addingTimeInterval(15)).map(\.id) == ["a"])
        list.lost(id: "a")
        #expect(list.visible(now: t0.addingTimeInterval(15)).isEmpty)
    }

    @Test func aPeerThatAdvertisesAPairedIdUnderAnotherNameIsShownUnderTheStoredName() {
        var list = FlingPeerList()
        list.setPaired(["idA": "Tony's Mac"])
        list.seen(id: "idA", name: "Definitely Not Tony", model: "Mac", now: t0)
        #expect(list.visible(now: t0).map(\.name) == ["Tony's Mac"])
    }

    /// REG-694: at most eight connections, one active transfer per peer, 10 s to handshake and 30 s idle.
    @Test func connectionCapsAndTimeouts() {
        var gate = FlingConnectionGate()
        for i in 0..<8 {
            let admitted = gate.admit(connection: i)
            #expect(admitted)
        }
        let ninth = gate.admit(connection: 8)
        #expect(!ninth)
        gate.release(connection: 3)
        let again = gate.admit(connection: 9)
        #expect(again)

        let first = gate.beginTransfer(peerID: "idA")
        let second = gate.beginTransfer(peerID: "idA")
        let other = gate.beginTransfer(peerID: "idB")
        #expect(first && !second && other)
        gate.endTransfer(peerID: "idA")
        let third = gate.beginTransfer(peerID: "idA")
        #expect(third)

        let policy = FlingTimeoutPolicy(connectedAt: t0, lastActivity: t0)
        #expect(!policy.shouldClose(now: t0.addingTimeInterval(9.9), handshaken: false))
        #expect(policy.shouldClose(now: t0.addingTimeInterval(10), handshaken: false))
        #expect(!policy.shouldClose(now: t0.addingTimeInterval(29.9), handshaken: true))
        #expect(policy.shouldClose(now: t0.addingTimeInterval(30), handshaken: true))
        let busy = FlingTimeoutPolicy(connectedAt: t0, lastActivity: t0.addingTimeInterval(25))
        #expect(!busy.shouldClose(now: t0.addingTimeInterval(40), handshaken: true))
    }

    /// REG-695: Everyone shows the name and model, Paired only shows only the id and closes the pairing listener, Off listens and advertises nothing.
    @Test func visibilityDecidesWhatIsAdvertisedAndWhichListenersRun() {
        let everyone = FlingVisibilityPolicy.plan(visibility: .everyone, id: "idA", name: "Tony's Mac", model: "Mac15,3", pairPort: 5555)
        #expect(everyone.advertise && everyone.transferListener && everyone.pairingListener)
        #expect(everyone.txt == ["v": "1", "id": "idA", "name": "Tony's Mac", "model": "Mac15,3", "pp": "5555"])

        let paired = FlingVisibilityPolicy.plan(visibility: .pairedOnly, id: "idA", name: "Tony's Mac", model: "Mac15,3", pairPort: 5555)
        #expect(paired.advertise && paired.transferListener && !paired.pairingListener)
        #expect(paired.txt == ["v": "1", "id": "idA"])

        let off = FlingVisibilityPolicy.plan(visibility: .off, id: "idA", name: "Tony's Mac", model: "Mac15,3", pairPort: 5555)
        #expect(!off.advertise && !off.transferListener && !off.pairingListener && off.txt.isEmpty)
    }

    /// REG-672: a stack id is remembered for ten minutes.
    @Test func aStackIdIsRememberedForTenMinutes() {
        var ledger = FlingReplayLedger()
        let id = UUID()
        let first = ledger.isReplay(id, now: t0)
        let second = ledger.isReplay(id, now: t0.addingTimeInterval(599))
        let third = ledger.isReplay(id, now: t0.addingTimeInterval(601))
        #expect(!first && second)
        // The repeat at 599 s does not extend the memory, so 601 s after the first sighting it is fresh again.
        #expect(!third)
        let other = ledger.isReplay(UUID(), now: t0.addingTimeInterval(601))
        #expect(!other)
    }
}
