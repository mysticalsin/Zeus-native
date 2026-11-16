import AppKit
import Observation
import SwiftUI
import ZeusCore

/// What the card on screen asks, and what happens to the answer. Sixty seconds without one counts as no.
@MainActor @Observable
final class FlingPromptModel {
    enum Kind: Equatable {
        /// `canAccept` is false on the Mac that started the pairing: it shows the same code with Cancel only.
        case pairing(code: String, peerName: String, canAccept: Bool)
        case offer(peerName: String, itemCount: Int, totalBytes: Int64)
    }

    let kind: Kind
    let deadline: Date
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let onAnswer: (Bool) -> Void
    private(set) var answered = false
    /// Ask each time: Accept becomes "Save" and "Copy", and the choice goes with the answer.
    let askWhere: Bool
    @ObservationIgnored private let onChoose: ((FlingSaveMode) -> Void)?

    init(kind: Kind, deadline: Date, clock: @escaping () -> Date, onAnswer: @escaping (Bool) -> Void,
         askWhere: Bool = false, onChoose: ((FlingSaveMode) -> Void)? = nil) {
        self.kind = kind; self.deadline = deadline; self.clock = clock; self.onAnswer = onAnswer
        self.askWhere = askWhere; self.onChoose = onChoose
    }

    /// Accepts and says where the files go. Only the first answer counts.
    func choose(_ mode: FlingSaveMode) {
        guard !answered else { return }
        answered = true
        onChoose?(mode)
    }

    /// Only the first answer counts.
    func answer(_ accept: Bool) {
        guard !answered else { return }
        answered = true
        onAnswer(accept)
    }

    /// Called about once a second. At the deadline the answer is no.
    func tick() {
        if !answered && clock() >= deadline { answer(false) }
    }

    func secondsLeft(now: Date? = nil) -> Int { max(0, Int(deadline.timeIntervalSince(now ?? clock()).rounded(.up))) }

    var codeText: String? {
        guard case .pairing(let code, _, _) = kind, code.count == 6 else { return nil }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }
}

struct FlingPromptCard: View {
    let model: FlingPromptModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch model.kind {
            case .pairing(_, let peer, let canAccept):
                Text(canAccept ? "\(peer) wants to pair" : "Pairing with \(peer)").font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
                Text(model.codeText ?? "").font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(Theme.bolt)
                    .accessibilityLabel("Code \(model.codeText ?? "")")
                Text(canAccept ? "Check that \(peer) shows the same six digits, then accept."
                               : "Check that \(peer) shows the same six digits. They accept on that Mac.")
                    .font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudSecondary).fixedSize(horizontal: false, vertical: true)
            case .offer(let peer, let count, let bytes):
                Text("\(peer) wants to send \(count) \(count == 1 ? "item" : "items")").font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudSecondary)
            }
            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Declines in \(model.secondsLeft(now: context.date)) s").font(TopBarStyle.label(9.5)).foregroundStyle(Theme.cloudQuiet)
                }
                Spacer(minLength: 8)
                button(canDecline: true)
                if canAccept {
                    if model.askWhere, case .offer = model.kind {
                        choice("Save", .downloads, id: "fling.prompt.save")
                        choice("Copy", .clipboard, id: "fling.prompt.copy")
                    } else {
                        button(canDecline: false)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.storm.opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var canAccept: Bool {
        if case .pairing(_, _, let can) = model.kind { return can }
        return true
    }

    private func choice(_ title: String, _ mode: FlingSaveMode, id: String) -> some View {
        Button { model.choose(mode) } label: {
            Text(title).font(TopBarStyle.label(11, .bold)).foregroundStyle(Color.black)
                .padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(Theme.bolt))
        }
        .buttonStyle(.plain)
        .ownedJourneyControl(id)
        .accessibilityLabel(mode == .downloads ? "Save to Downloads" : "Copy to the clipboard")
    }

    @ViewBuilder
    private func button(canDecline: Bool) -> some View {
        let isPairingStarter: Bool = { if case .pairing(_, _, false) = model.kind { return true } else { return false } }()
        let title = canDecline ? (isPairingStarter ? "Cancel" : "Decline") : "Accept"
        Button { model.answer(!canDecline) } label: {
            Text(title).font(TopBarStyle.label(11, .bold)).foregroundStyle(canDecline ? Theme.cloudPrimary : Color.black)
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(Capsule().fill(canDecline ? Color.white.opacity(0.12) : Theme.bolt))
        }
        .buttonStyle(.plain)
        .ownedJourneyControl(canDecline ? "fling.prompt.decline" : "fling.prompt.accept")
        .accessibilityLabel(title)
    }
}

private final class FlingPromptHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class FlingPromptWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows the card under the notch, in a panel that never takes the keyboard, and takes it down when the answer is in.
/// Pairing outranks an offer, and only one card is ever on screen.
@MainActor
final class FlingPromptPanelController {
    private let fling: FlingService
    private var window: FlingPromptWindow?
    private var model: FlingPromptModel?
    private var shownKey: String?
    private var timer: Timer?

    init(fling: FlingService) {
        self.fling = fling
        track()
    }

    private func track() {
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
    }

    private func refresh() {
        let pairing = fling.pairingPrompt, offer = fling.pendingOffer
        let key = pairing.map { "p:\($0.code):\($0.peerID)" } ?? offer.map { "o:\($0.stackID)" }
        guard key != shownKey else { return }
        shownKey = key
        timer?.invalidate(); timer = nil
        guard let key else { hide(); return }
        let deadline = Date().addingTimeInterval(FlingLimits.promptTimeout)
        let next: FlingPromptModel
        if let pairing {
            let service = fling
            next = FlingPromptModel(kind: .pairing(code: pairing.code, peerName: pairing.peerName, canAccept: pairing.role == .responder),
                                    deadline: deadline, clock: Date.init, onAnswer: { accept in service.answerPairing(accept: accept) })
        } else if let offer {
            let service = fling
            next = FlingPromptModel(kind: .offer(peerName: offer.peerName, itemCount: offer.itemCount, totalBytes: offer.totalBytes),
                                    deadline: deadline, clock: Date.init, onAnswer: { accept in service.answerOffer(accept: accept) },
                                    askWhere: service.asksWhere, onChoose: { mode in service.answerOffer(accept: true, saveMode: mode) })
        } else { _ = key; return }
        model = next
        show(next)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak next] _ in MainActor.assumeIsolated { next?.tick() } }
    }

    private func show(_ model: FlingPromptModel) {
        let host = FlingPromptHostingView(rootView: FlingPromptCard(model: model))
        let panel = window ?? FlingPromptWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        let size = host.fittingSize
        panel.setContentSize(size)
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 48))
        window = panel
        panel.orderFrontRegardless()
    }

    private func hide() {
        window?.orderOut(nil)
        model = nil
    }
}
