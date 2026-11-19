import Foundation
import ZeusCore
import ZeusFling

/// A stand-in for Fling in snapshots: it draws states and does nothing.
@MainActor
final class FlingSnapshotFling: FlingSending {
    var isEnabled = true
    var localNetworkDenied = false
    var nearby: [FlingNearbyPeer] = []
    var pairingPrompt: FlingPairingPrompt?
    var pendingOffer: FlingOfferPrompt?
    var activity: [FlingActivity] = []
    var justSent: Set<String> = []
    var lastProblem: String?
    func turnOn() {}
    func send(_ items: [TopBarModel.ShelfItem], to target: FlingTarget, gesture: FlingGesture) {}
    func pair(with peerID: String) {}
    func answerPairing(accept: Bool) {}
    func answerOffer(accept: Bool) {}
    func cancelAll() {}

    private static let macs = [
        FlingNearbyPeer(id: "a", name: "Alpha Mac", model: "Mac15,3", paired: true),
        FlingNearbyPeer(id: "b", name: "Beta Mac", model: "Mac14,2", paired: true),
        FlingNearbyPeer(id: "c", name: "Gamma Mac", model: "Mac13,1", paired: false),
    ]

    private static func items(stack: UUID?) -> [TopBarModel.ShelfItem] {
        ["Glass", "Basso", "Ping"].map {
            TopBarModel.ShelfItem(url: URL(fileURLWithPath: "/System/Library/Sounds/\($0).aiff"), origin: .fling(peer: "Alpha Mac"), stackID: stack, verified: true)
        }
    }

    /// The Shelf page in the states a person meets: off, Macs nearby, a send under way, refused, and a stack.
    static var shelfStates: [(name: String, fling: FlingSnapshotFling, items: [TopBarModel.ShelfItem])] {
        let off = FlingSnapshotFling(); off.isEnabled = false
        let nearby = FlingSnapshotFling(); nearby.nearby = macs
        let sending = FlingSnapshotFling(); sending.nearby = macs
        sending.activity = [FlingActivity(stackID: UUID(), direction: .send, peerID: "b", peerName: "Beta Mac", fraction: 0.6)]
        sending.justSent = ["a"]
        let denied = FlingSnapshotFling(); denied.localNetworkDenied = true
        let stack = FlingSnapshotFling(); stack.nearby = macs
        let stackID = UUID()
        return [
            ("off", off, [TopBarModel.ShelfItem(url: URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff"))]),
            ("nearby", nearby, items(stack: nil)),
            ("sending", sending, items(stack: nil)),
            ("denied", denied, []),
            ("stack", stack, items(stack: stackID) + [TopBarModel.ShelfItem(url: URL(fileURLWithPath: "/System/Library/Sounds/Funk.aiff"))]),
        ]
    }
}
