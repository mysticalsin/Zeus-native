import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers
import ZeusCore

/// The strip above the Shelf's files: off, refused, or the Macs nearby with AirDrop last.
struct FlingNearbyStrip: View {
    let fling: any FlingSending
    let topBar: TopBarModel

    static func avatarID(_ peerID: String) -> String { "fling.avatar.\(peerID)" }

    var body: some View {
        Group {
            if !fling.isEnabled { offRow }
            else if fling.localNetworkDenied { deniedRow }
            else { peersRow }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var offRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "paperplane").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.cloudSecondary)
            Text("Send files to nearby Macs").font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary)
            Text("Off until you turn it on").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudQuiet)
            Spacer(minLength: 8)
            Button { fling.turnOn() } label: {
                Text("Turn on").font(TopBarStyle.label(10.5, .bold)).foregroundStyle(Theme.bolt)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().strokeBorder(Theme.bolt.opacity(0.7), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .ownedJourneyControl("fling.turnOn")
            .accessibilityLabel("Turn on Fling")
        }
        .padding(.horizontal, 6).frame(height: 30)
    }

    private var deniedRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "network.slash").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ember)
            Text("Local Network is off for Zeus, so nearby Macs cannot be found.")
                .font(TopBarStyle.label(10.5, .medium)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
            Spacer(minLength: 8)
            Button { NSWorkspace.shared.open(FlingService.localNetworkSettingsURL) } label: {
                Text("Open Settings").font(TopBarStyle.label(10.5, .bold)).foregroundStyle(Theme.bolt)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().strokeBorder(Theme.bolt.opacity(0.7), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .ownedJourneyControl("fling.openLocalNetwork")
            .accessibilityLabel("Open System Settings, Local Network")
        }
        .padding(.horizontal, 6).frame(height: 30)
    }

    @ViewBuilder
    private var peersRow: some View {
        let row = HStack(alignment: .top, spacing: 10) {
            if fling.nearby.isEmpty {
                Text("Looking for Macs running Zeus").font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudQuiet)
                    .frame(height: 50)
            }
            ForEach(fling.nearby) { peer in FlingAvatar(peer: peer, fling: fling, topBar: topBar) }
            FlingAirDropTile(fling: fling, topBar: topBar)
        }
        .padding(.horizontal, 4)
        // A snapshot cannot draw a scroll view, so it draws the row itself.
        if TopBarStyle.isSnapshot {
            row.frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        } else {
            ScrollView(.horizontal, showsIndicators: false) { row }.frame(height: 56)
        }
    }
}

/// A nearby Mac: a drop target for files, a pairing button when it is not paired yet, and a ring while a stack moves.
private struct FlingAvatar: View {
    let peer: FlingNearbyPeer
    let fling: any FlingSending
    let topBar: TopBarModel
    @State private var targeted = false

    var body: some View {
        let moving = fling.activity.first { $0.peerID == peer.id }
        let done = fling.justSent.contains(peer.id)
        Button {
            if !peer.paired { fling.pair(with: peer.id) }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle().fill(Color.white.opacity(targeted ? 0.16 : 0.07))
                    Circle().strokeBorder(targeted ? Theme.bolt : TopBarStyle.tileStroke, lineWidth: targeted ? 2 : 1)
                    Image(systemName: done ? "checkmark" : "laptopcomputer").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(done ? Theme.leaf : Theme.cloudPrimary)
                    if let moving {
                        Circle().trim(from: 0, to: max(0.02, moving.fraction))
                            .stroke(Theme.bolt, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    if peer.paired {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 9)).foregroundStyle(Theme.leaf)
                            .offset(x: 12, y: 12)
                    }
                }
                .frame(width: 34, height: 34)
                Text(peer.name).font(TopBarStyle.label(9.5, .medium)).foregroundStyle(Theme.cloudPrimary).lineLimit(1).frame(width: 64)
                if !peer.paired { Text("Pair").font(TopBarStyle.label(8.5, .bold)).foregroundStyle(Theme.bolt) }
            }
        }
        .buttonStyle(.plain)
        .ownedJourneyControl(FlingNearbyStrip.avatarID(peer.id))
        .accessibilityLabel(peer.paired ? "\(peer.name), paired" : "\(peer.name), not paired, press to pair")
        .live { $0.onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard peer.paired else { return false }
            FlingDropHandler.perform(providers: providers, to: .peer(id: peer.id), fling: fling, topBar: topBar)
            return true
        } }
        .contextMenu {
            if peer.paired && !topBar.shelf.isEmpty {
                Button("Send the Shelf (\(topBar.shelf.count))") { fling.send(topBar.shelf, to: .peer(id: peer.id), gesture: .menu) }
            }
        }
    }
}

private struct FlingAirDropTile: View {
    let fling: any FlingSending
    let topBar: TopBarModel
    @State private var targeted = false

    var body: some View {
        Button {
            guard !topBar.shelf.isEmpty else { return }
            fling.send(topBar.shelf, to: .airDrop, gesture: .button)
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle().fill(Color.white.opacity(targeted ? 0.16 : 0.07))
                    Circle().strokeBorder(targeted ? Theme.bolt : TopBarStyle.tileStroke, lineWidth: targeted ? 2 : 1)
                    Image(systemName: "airplayaudio").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.sky)
                }
                .frame(width: 34, height: 34)
                Text("AirDrop").font(TopBarStyle.label(9.5, .medium)).foregroundStyle(Theme.cloudPrimary).frame(width: 64)
            }
        }
        .buttonStyle(.plain)
        .ownedJourneyControl("fling.airdrop")
        .accessibilityLabel("AirDrop, for iPhone and other devices")
        .live { $0.onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            FlingDropHandler.perform(providers: providers, to: .airDrop, fling: fling, topBar: topBar)
            return true
        } }
    }
}

/// What the avatars' drop targets do. Kept apart from the views so a journey can call exactly this.
enum FlingDropHandler {
    /// Reads the dropped file URLs, finds the matching Shelf items (or makes plain ones for files from Finder) and
    /// sends them. The drop is the gesture.
    @MainActor
    static func perform(providers: [NSItemProvider], to target: FlingTarget, fling: any FlingSending, topBar: TopBarModel,
                        gesture: FlingGesture = .drop) {
        let box = LoadedURLs()
        let group = DispatchGroup()
        for (index, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                box.set(url, at: index)
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                let urls = box.ordered()
                guard !urls.isEmpty else { return }
                let items = urls.map { url in topBar.shelf.first { $0.url == url } ?? TopBarModel.ShelfItem(url: url) }
                fling.send(items, to: target, gesture: gesture)
            }
        }
    }
}

/// URLs read from item providers on any queue, kept in provider order.
private final class LoadedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var found: [Int: URL] = [:]
    func set(_ url: URL?, at index: Int) { lock.lock(); defer { lock.unlock() }; if let url { found[index] = url } }
    func ordered() -> [URL] { lock.lock(); defer { lock.unlock() }; return found.keys.sorted().compactMap { found[$0] } }
}

/// A "Fling to" list for one Shelf item or a whole stack: paired Macs, Macs to pair with, and AirDrop.
struct FlingPickerMenu: View {
    let items: [TopBarModel.ShelfItem]
    let fling: any FlingSending
    var tint: Color = Theme.cloudSecondary

    var body: some View {
        Menu {
            ForEach(fling.nearby.filter(\.paired)) { peer in
                Button(peer.name) { fling.send(items, to: .peer(id: peer.id), gesture: .menu) }
            }
            ForEach(fling.nearby.filter { !$0.paired }) { peer in
                Button("Pair with \(peer.name)") { fling.pair(with: peer.id) }
            }
            Divider()
            Button("AirDrop") { fling.send(items, to: .airDrop, gesture: .menu) }
        } label: {
            Image(systemName: "paperplane").font(.system(size: 9, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Fling to")
    }
}

// MARK: Flick

/// Collects the points of one drag and says what it was: a drop, a send to a Mac, or "pick one".
@MainActor
final class FlingFlickTracker {
    private var samples: [FlickSample] = []
    private let sensitivity: FlickSensitivity

    init(sensitivity: FlickSensitivity) { self.sensitivity = sensitivity }

    func reset() { samples = [] }
    func add(_ point: CGPoint, at time: TimeInterval) { samples.append(FlickSample(time: time, point: point)) }

    /// `peerCount` is the number of paired Macs a flick may reach.
    func finish(peerCount: Int) -> FlickOutcome {
        let outcome = FlingFlick.classify(samples: samples, sensitivity: sensitivity, peers: peerCount)
        samples = []
        return outcome
    }
}

enum FlingFlickAction {
    /// Applies an outcome. `peers` are the paired Macs in strip order, left to right. A flick is the gesture.
    @MainActor
    static func perform(_ outcome: FlickOutcome, items: [TopBarModel.ShelfItem], peers: [FlingNearbyPeer],
                        fling: any FlingSending, openPicker: () -> Void) {
        switch outcome {
        case .drop: break
        case .picker: openPicker()
        case .send(let index):
            guard peers.indices.contains(index) else { return }
            fling.send(items, to: .peer(id: peers[index].id), gesture: .flick)
        }
    }
}

/// The paper plane on a cell: press, move and let go fast to send the file to a nearby Mac.
struct FlingFlickHandle: View {
    let items: [TopBarModel.ShelfItem]
    let fling: any FlingSending
    @State private var tracker: FlingFlickTracker
    @State private var offset = CGSize.zero
    @State private var gone = false
    @State private var picker = false

    init(items: [TopBarModel.ShelfItem], fling: any FlingSending, sensitivity: FlickSensitivity) {
        self.items = items
        self.fling = fling
        _tracker = State(initialValue: FlingFlickTracker(sensitivity: sensitivity))
    }

    var body: some View {
        Image(systemName: "paperplane.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.bolt)
            .frame(width: 24, height: 24)
            .offset(offset).opacity(gone ? 0 : 1)
            .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { value in
                    tracker.add(value.location, at: ProcessInfo.processInfo.systemUptime)
                    if !Motion.reduced { offset = value.translation }
                }
                .onEnded { value in
                    tracker.add(value.location, at: ProcessInfo.processInfo.systemUptime)
                    let peers = fling.nearby.filter(\.paired)
                    let outcome = tracker.finish(peerCount: peers.count)
                    FlingFlickAction.perform(outcome, items: items, peers: peers, fling: fling, openPicker: { picker = true })
                    if case .send = outcome {
                        // Fly off along the flick, never further than 240 points; Reduce Motion only fades.
                        let motion = FlingGeometry.flyOff(translation: value.predictedEndTranslation, reduceMotion: Motion.reduced)
                        // Reduce Motion fades; otherwise it travels on the peek spring.
                        withAnimation(motion.fadeOnly ? .easeOut(duration: MotionTokens.crossfadeDuration) : Motion.live(MotionTokens.peekContent)) { offset = motion.offset; gone = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { gone = false; offset = .zero }
                    } else {
                        withAnimation(Motion.live(MotionTokens.panelResize)) { offset = .zero }
                    }
                })
            .popover(isPresented: $picker) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(fling.nearby.filter(\.paired)) { peer in
                        Button(peer.name) { picker = false; fling.send(items, to: .peer(id: peer.id), gesture: .flick) }
                    }
                    Button("AirDrop") { picker = false; fling.send(items, to: .airDrop, gesture: .flick) }
                }.padding(10)
            }
            .accessibilityLabel("Flick to send")
            .accessibilityHint("Press and flick toward a nearby Mac, or flick up to choose one")
    }
}
