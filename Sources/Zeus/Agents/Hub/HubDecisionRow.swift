import Foundation
import ZeusCore
#if canImport(SwiftUI) && canImport(AppKit)
import AppKit
import Carbon.HIToolbox
import SwiftUI
#endif

/// Red line for the inline decision row. The host fails until that row's accessibility label
/// matches the focus order in the experience contract: group header, row, Deny, Approve,
/// transcript, reply, Send, Open. Reduce Motion must request zero offset and scale 1.
/// Deny is never the default action.
enum HubDecisionRowTestHost {
    static let contract = "group header, row, Deny, Approve, transcript, reply, Send, Open"

    static func verify() {
        let label = HubDecisionRow.accessibilityContractLabel
        precondition(label == contract, "accessibility label \(label) does not match the PR 7 contract")
        precondition(HubDecisionRow.ownedAccessibilityLabels(showingApproval: true) == ["Deny", "Approve", "Reply", "Send"])
        precondition(HubDecisionRow.ownedAccessibilityLabels(showingApproval: false) == ["Reply", "Send"])
        let still = HubDecisionRow.reduceMotionRequest
        precondition(still.offset == 0 && still.scale == 1, "Reduce Motion must request zero offset and scale 1")
        let moving = HubDecisionRow.motion(reduceMotion: false)
        precondition(moving.offset == 8 && moving.scale == 0.985)
        precondition(HubDecisionRow.motion(reduceMotion: true) == still)
        precondition(HubDecisionRow.animates(reduceMotion: true) == false)
        precondition(HubDecisionRow.denyIsDefaultAction == false)
        precondition(HubDecisionRow.approveIsDefaultAction == false)
        precondition(HubDecisionRow.sendIsDefaultAction == false)
        precondition(HubDecisionRow.askIsButton == false)
        precondition(HubDecisionRow.countdown(12) == "12 s left, then it's denied.")
        precondition(HubDecisionRow.queuedHint(thisRowIsQueued: true, count: 1) == "Waiting behind the approval above. Buttons appear when it reaches the front.")
        precondition(HubDecisionRow.queuedHint(thisRowIsQueued: true, count: 2) == "2 waiting ahead. Waiting behind the approval above. Buttons appear when it reaches the front.")
        precondition(HubDecisionRow.queuedHint(thisRowIsQueued: false, count: 0) == nil)
        precondition(HubDecisionRow.queuedHint(thisRowIsQueued: false, count: 1) == "1 waiting")
        precondition(HubDecisionRow.queuedHint(thisRowIsQueued: false, count: 2) == "2 waiting")
        let priorities = HubFocusTarget.selectedApprovalOrder.map { HubDecisionFocus.priority($0) }
        precondition(zip(priorities, priorities.dropFirst()).allSatisfy { $0 > $1 })
        precondition(HubDecisionFocus.priority(.row) > HubDecisionFocus.toolPriority)
        precondition(HubDecisionFocus.toolPriority > HubDecisionFocus.bodyPriority)
        precondition(HubDecisionFocus.bodyPriority > HubDecisionFocus.priority(.deny))
        precondition(HubDecisionFocus.priority(.approve) > HubDecisionFocus.countdownPriority)
        precondition(HubDecisionFocus.countdownPriority > HubDecisionFocus.queuePriority)
        precondition(HubDecisionFocus.queuePriority > HubDecisionFocus.priority(.transcript))
        precondition(HubDecisionFocus.priority(.send) > HubDecisionFocus.receiptPriority)
        precondition(HubDecisionFocus.receiptPriority > HubDecisionFocus.priority(.open))
    }
}

// MARK: - Contract

/// Offset and scale the row asks for. Reduce Motion is zero and one. Motion uses the page rise.
struct HubDecisionMotion: Equatable {
    var offset: Double
    var scale: Double

    static func request(reduceMotion: Bool) -> HubDecisionMotion {
        reduceMotion ? HubDecisionMotion(offset: 0, scale: 1) : HubDecisionMotion(offset: 8, scale: 0.985)
    }
}

/// Where this row sits in the focus order. Higher is earlier. The numbers leave room for the
/// transcript between Approve and the reply field when a later page places that view beside this one.
enum HubDecisionFocus {
    static func priority(_ target: HubFocusTarget) -> Double {
        let order = HubFocusTarget.selectedApprovalOrder
        guard let index = order.firstIndex(of: target) else { return 0 }
        return Double(order.count - index) * 10
    }

    static var toolPriority: Double { priority(.row) - 4 }
    static var bodyPriority: Double { priority(.row) - 6 }
    static var countdownPriority: Double { priority(.approve) - 5 }
    static var queuePriority: Double { priority(.approve) - 6 }
    static var receiptPriority: Double { priority(.send) - 5 }

    static func spoken(_ target: HubFocusTarget) -> String {
        switch target {
        case .outside: "outside"
        case .tabRow: "tab row"
        case .groupHeader: "group header"
        case .row: "row"
        case .picker: "picker"
        case .deny: "Deny"
        case .approve: "Approve"
        case .transcript: "transcript"
        case .copy: "Copy"
        case .reply: "reply"
        case .send: "Send"
        case .open: "Open"
        }
    }

    static var accessibilityLabel: String {
        HubFocusTarget.selectedApprovalOrder.map { spoken($0) }.joined(separator: ", ")
    }
}

/// Words and motion the row draws and the host checks. One source, so a label cannot drift from the contract.
enum HubDecisionContract {
    static let denyTitle = "Deny"
    static let approveTitle = "Approve"
    static let replyLabel = "Reply"
    static let sendTitle = "Send"
    static let highRiskWord = "High risk"
    static let hiddenDetails = "Details hidden (Settings > Privacy)"

    static var accessibilityContractLabel: String { HubDecisionFocus.accessibilityLabel }

    static func ownedAccessibilityLabels(showingApproval: Bool) -> [String] {
        var labels: [String] = []
        if showingApproval {
            labels.append(denyTitle)
            labels.append(approveTitle)
        }
        labels.append(replyLabel)
        labels.append(sendTitle)
        return labels
    }

    static var reduceMotionRequest: HubDecisionMotion { motion(reduceMotion: true) }

    static func motion(reduceMotion: Bool) -> HubDecisionMotion {
        .request(reduceMotion: reduceMotion)
    }

    /// Reduce Motion changes in one frame. The height spring runs only when this is true.
    static func animates(reduceMotion: Bool) -> Bool { !reduceMotion }

    /// Deny is never the default action. Approve and Send are not either: Return stays in the reply field.
    static let denyIsDefaultAction = false
    static let approveIsDefaultAction = false
    static let sendIsDefaultAction = false

    /// Ask is the existing keyboard verdict. It is not a button.
    static let askIsButton = false

    static func countdown(_ seconds: Int) -> String {
        "\(max(seconds, 0)) s left, then it's denied."
    }

    /// Visible queued-count hint. A row that is itself waiting uses the sentence from the mock.
    /// A row that is showing names how many are behind it.
    static func queuedHint(thisRowIsQueued: Bool, count: Int) -> String? {
        let waiting = max(count, 0)
        if thisRowIsQueued {
            if waiting > 1 {
                return "\(waiting) waiting ahead. Waiting behind the approval above. Buttons appear when it reaches the front."
            }
            return "Waiting behind the approval above. Buttons appear when it reaches the front."
        }
        guard waiting > 0 else { return nil }
        return waiting == 1 ? "1 waiting" : "\(waiting) waiting"
    }

    static func queuedAccessibilityLabel(thisRowIsQueued: Bool, count: Int) -> String? {
        guard let hint = queuedHint(thisRowIsQueued: thisRowIsQueued, count: count) else { return nil }
        if thisRowIsQueued { return hint }
        let waiting = max(count, 0)
        return waiting == 1 ? "1 waiting behind this approval." : "\(waiting) waiting behind this approval."
    }

    static func denyHint(answerKeysOn: Bool) -> String {
        answerKeysOn ? "Stops this once. Control-Option-N denies." : "Stops this once."
    }

    static func approveHint(answerKeysOn: Bool, allowsAsk: Bool) -> String {
        var hint = answerKeysOn ? "Lets this run once. Control-Option-Y approves." : "Lets this run once."
        if answerKeysOn, allowsAsk { hint += " Control-Option-O asks." }
        return hint
    }
}

#if canImport(SwiftUI) && canImport(AppKit)

/// Inline approval on a session row: Deny and Approve, Ask from the keyboard, the queued-count hint,
/// and the quick-reply field with Send. Reuses `CardButton` and `DiffPreview`. No card above the page.
struct HubDecisionRow: View {
    var request: HubDecisionRequest?
    var queue: HubDecisionQueue
    var scope: HubDecisionScope
    @Binding var reply: String
    var receipt: String?
    var answerKeysOn: Bool
    var detailsHidden: Bool
    /// Nil follows the system Reduce Motion setting.
    var reduceMotion: Bool?
    var onVerdict: (HubApprovalVerdict) -> Void
    var onSend: () -> Void

    static var accessibilityContractLabel: String { HubDecisionContract.accessibilityContractLabel }
    static func ownedAccessibilityLabels(showingApproval: Bool) -> [String] {
        HubDecisionContract.ownedAccessibilityLabels(showingApproval: showingApproval)
    }
    static var reduceMotionRequest: HubDecisionMotion { HubDecisionContract.reduceMotionRequest }
    static func motion(reduceMotion: Bool) -> HubDecisionMotion { HubDecisionContract.motion(reduceMotion: reduceMotion) }
    static func animates(reduceMotion: Bool) -> Bool { HubDecisionContract.animates(reduceMotion: reduceMotion) }
    static var denyIsDefaultAction: Bool { HubDecisionContract.denyIsDefaultAction }
    static var approveIsDefaultAction: Bool { HubDecisionContract.approveIsDefaultAction }
    static var sendIsDefaultAction: Bool { HubDecisionContract.sendIsDefaultAction }
    static var askIsButton: Bool { HubDecisionContract.askIsButton }
    static func countdown(_ seconds: Int) -> String { HubDecisionContract.countdown(seconds) }
    static func queuedHint(thisRowIsQueued: Bool, count: Int) -> String? {
        HubDecisionContract.queuedHint(thisRowIsQueued: thisRowIsQueued, count: count)
    }

    init(
        request: HubDecisionRequest? = nil,
        queue: HubDecisionQueue = .none,
        scope: HubDecisionScope = .row,
        reply: Binding<String>,
        receipt: String? = nil,
        answerKeysOn: Bool = false,
        detailsHidden: Bool = false,
        reduceMotion: Bool? = nil,
        onVerdict: @escaping (HubApprovalVerdict) -> Void = { _ in },
        onSend: @escaping () -> Void = {}
    ) {
        #if DEBUG
        HubDecisionRowTestHost.verify()
        #endif
        self.request = request
        self.queue = queue
        self.scope = scope
        self._reply = reply
        self.receipt = receipt
        self.answerKeysOn = answerKeysOn
        self.detailsHidden = detailsHidden
        self.reduceMotion = reduceMotion
        self.onVerdict = onVerdict
        self.onSend = onSend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if scope != .reply {
                decision
                    .accessibilitySortPriority(HubDecisionFocus.priority(.deny))
            }
            if scope != .approval {
                replyBlock
                    .accessibilitySortPriority(HubDecisionFocus.priority(.reply))
            }
        }
        .accessibilityElement(children: .contain)
        .animation(rowAnimation, value: phase)
        .animation(rowAnimation, value: receipt)
        .transaction { transaction in
            if !animating { transaction.disablesAnimations = true }
        }
        .background {
            HubDecisionKeyMonitor(active: keysActive, allowsAsk: request?.allowsAsk == true, onVerdict: onVerdict)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private var reduced: Bool { reduceMotion ?? Motion.reduced }
    private var animating: Bool { Self.animates(reduceMotion: reduced) }
    private var rowMotion: HubDecisionMotion { Self.motion(reduceMotion: reduced) }
    /// One spring for the height change. Nil under Reduce Motion, so the block does not rise or scale.
    private var rowAnimation: Animation? {
        guard animating else { return nil }
        return Motion.page(reduceMotion: false)
    }

    private var keysActive: Bool { phase == .showing && answerKeysOn }

    private enum Phase: Equatable { case hidden, queued, showing }

    private var phase: Phase {
        guard scope != .reply else { return .hidden }
        if queue.thisRowIsQueued { return .queued }
        if request != nil { return .showing }
        return .hidden
    }

    private var replyHasText: Bool {
        !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var rowTransition: AnyTransition {
        let motion = rowMotion
        // Reduce Motion asks for zero offset and scale 1, so the block appears in one frame.
        if motion.offset == 0, motion.scale == 1 { return .identity }
        return .opacity
            .combined(with: .offset(y: CGFloat(motion.offset)))
            .combined(with: .scale(scale: CGFloat(motion.scale), anchor: .top))
    }

    @ViewBuilder
    private var decision: some View {
        if phase != .hidden {
            VStack(alignment: .leading, spacing: 8) {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .accessibilityHidden(true)
                if let request {
                    toolLine(request)
                    decisionBody(request)
                }
                if phase == .showing, let request {
                    buttonRow(request)
                    if let seconds = request.secondsLeft {
                        Text(Self.countdown(seconds))
                            .font(.system(size: 10.5, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.cloudQuiet)
                            .accessibilityLabel(Self.countdown(seconds))
                            .accessibilitySortPriority(HubDecisionFocus.countdownPriority)
                    }
                }
                if let hint = Self.queuedHint(thisRowIsQueued: queue.thisRowIsQueued, count: queue.count),
                   let spoken = HubDecisionContract.queuedAccessibilityLabel(thisRowIsQueued: queue.thisRowIsQueued, count: queue.count) {
                    Text(hint)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.cloudQuiet)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(spoken)
                        .accessibilitySortPriority(HubDecisionFocus.queuePriority)
                }
            }
            .padding(.top, 8)
            .transition(rowTransition)
        }
    }

    private func toolLine(_ request: HubDecisionRequest) -> some View {
        HStack(spacing: 6) {
            Text(request.tool)
                .foregroundStyle(Theme.ember)
            if request.highRisk {
                Text("·")
                    .foregroundStyle(Theme.ember)
                    .accessibilityHidden(true)
                Text(HubDecisionContract.highRiskWord)
                    .foregroundStyle(Theme.danger)
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(request.highRisk ? "\(request.tool), \(HubDecisionContract.highRiskWord)" : request.tool)
        .accessibilitySortPriority(HubDecisionFocus.toolPriority)
    }

    @ViewBuilder
    private func decisionBody(_ request: HubDecisionRequest) -> some View {
        if detailsHidden {
            Text(HubDecisionContract.hiddenDetails)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.cloudSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Details hidden")
                .accessibilitySortPriority(HubDecisionFocus.bodyPriority)
        } else if let diff = request.diff {
            DiffPreview(diff: diff)
                .accessibilitySortPriority(HubDecisionFocus.bodyPriority)
        } else if let command = request.command, !command.isEmpty {
            Text(CommandDisplay.plain(command))
                .accessibilityLabel(command)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.cloudPrimary)
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilitySortPriority(HubDecisionFocus.bodyPriority)
        } else if let question = request.question, !question.isEmpty {
            Text(question)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.cloudPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(question)
                .accessibilitySortPriority(HubDecisionFocus.bodyPriority)
        }
    }

    private func buttonRow(_ request: HubDecisionRequest) -> some View {
        HStack(spacing: 8) {
            verdictButton(.deny, tint: Theme.cloudSecondary, filled: false) { onVerdict(.deny) }
            verdictButton(.approve, tint: Theme.ember, filled: true) { onVerdict(.allow) }
            if Self.askIsButton {
                verdictButton(.ask, tint: Theme.cloudSecondary, filled: false) { onVerdict(.ask) }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func verdictButton(_ role: VerdictRole, tint: Color, filled: Bool, action: @escaping () -> Void) -> some View {
        applyingDefault(CardButton(title: role.title, tint: tint, filled: filled, action: action)
            .accessibilityLabel(role.title)
            .accessibilityHint(hint(for: role))
            .accessibilitySortPriority(role.priority),
            isDefault: role.isDefaultAction)
    }

    private func hint(for role: VerdictRole) -> String {
        switch role {
        case .deny: HubDecisionContract.denyHint(answerKeysOn: answerKeysOn)
        case .approve: HubDecisionContract.approveHint(answerKeysOn: answerKeysOn, allowsAsk: request?.allowsAsk == true)
        case .ask: "Asks from the keyboard."
        }
    }

    private var replyBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                NotchTextField(text: $reply, placeholder: HubDecisionContract.replyLabel, onSubmit: onSend)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .accessibilityLabel(HubDecisionContract.replyLabel)
                    .accessibilitySortPriority(HubDecisionFocus.priority(.reply))
                applyingDefault(
                    CardButton(title: HubDecisionContract.sendTitle, tint: Theme.accent, filled: true, action: onSend)
                        .opacity(replyHasText ? 1 : 0.4)
                        .animation(animating ? .easeOut(duration: Motion.feedbackDuration) : nil, value: replyHasText)
                        .accessibilityLabel(HubDecisionContract.sendTitle)
                        .accessibilityHint(replyHasText ? "Sends the reply. Approval comes first." : "Type something first.")
                        .accessibilitySortPriority(HubDecisionFocus.priority(.send)),
                    isDefault: Self.sendIsDefaultAction)
            }
            if let receipt, !receipt.isEmpty {
                Text(receipt)
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(Theme.cloudQuiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(receipt)
                    .accessibilitySortPriority(HubDecisionFocus.receiptPriority)
            }
        }
    }

    /// Neither verdict is the window default. A default shortcut would make Return deny or approve.
    @ViewBuilder
    private func applyingDefault<V: View>(_ view: V, isDefault: Bool) -> some View {
        if isDefault {
            view.keyboardShortcut(.defaultAction)
        } else {
            view
        }
    }
}

/// Which part of the decision a caller places. `.row` is the approval and the reply together.
enum HubDecisionScope: Equatable {
    case approval
    case reply
    case row
}

/// How many approvals are waiting, and whether this row is the one behind the live pair of buttons.
struct HubDecisionQueue: Equatable {
    var thisRowIsQueued: Bool
    var count: Int

    static let none = HubDecisionQueue(thisRowIsQueued: false, count: 0)
}

/// Plain values for one inline decision. The machines that change state stay outside this view.
struct HubDecisionRequest: Equatable {
    var tool: String
    var highRisk: Bool
    var command: String?
    var question: String?
    var diff: FileDiff?
    var secondsLeft: Int?
    /// Control-Option-O asks only when this is true. There is still no Ask button.
    var allowsAsk: Bool

    init(tool: String, highRisk: Bool = false, command: String? = nil, question: String? = nil,
         diff: FileDiff? = nil, secondsLeft: Int? = nil, allowsAsk: Bool = true) {
        self.tool = tool
        self.highRisk = highRisk
        self.command = command
        self.question = question
        self.diff = diff
        self.secondsLeft = secondsLeft
        self.allowsAsk = allowsAsk
    }
}

/// Deny, Approve, and the keyboard-only Ask verdict. Ask is drawn only if the contract grows a button.
private enum VerdictRole {
    case deny, approve, ask

    var title: String {
        switch self {
        case .deny: HubDecisionContract.denyTitle
        case .approve: HubDecisionContract.approveTitle
        case .ask: "Ask"
        }
    }

    var isDefaultAction: Bool {
        switch self {
        case .deny: HubDecisionRow.denyIsDefaultAction
        case .approve: HubDecisionRow.approveIsDefaultAction
        case .ask: false
        }
    }

    var priority: Double {
        switch self {
        case .deny: HubDecisionFocus.priority(.deny)
        case .approve: HubDecisionFocus.priority(.approve)
        case .ask: HubDecisionFocus.priority(.approve) - 1
        }
    }
}

/// Control-Option-Y, N, and O answer the showing approval. The monitor is installed only while it is showing
/// and the keyboard setting is on, so the same keys do nothing the rest of the time.
private struct HubDecisionKeyMonitor: NSViewRepresentable {
    var active: Bool
    var allowsAsk: Bool
    var onVerdict: (HubApprovalVerdict) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.sync(active: active, allowsAsk: allowsAsk, onVerdict: onVerdict)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.sync(active: active, allowsAsk: allowsAsk, onVerdict: onVerdict)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        MainActor.assumeIsolated { coordinator.stop() }
    }

    @MainActor
    final class Coordinator {
        private var monitor: Any?
        private var allowsAsk = false
        private var onVerdict: (HubApprovalVerdict) -> Void = { _ in }

        func sync(active: Bool, allowsAsk: Bool, onVerdict: @escaping (HubApprovalVerdict) -> Void) {
            self.allowsAsk = allowsAsk
            self.onVerdict = onVerdict
            if active { start() } else { stop() }
        }

        private func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return MainActor.assumeIsolated { self.handle(event) }
            }
        }

        /// Y approves, N denies, O asks. Repeats are swallowed so a held key cannot answer twice.
        private func handle(_ event: NSEvent) -> NSEvent? {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
            guard flags == [.control, .option] else { return event }
            let verdict: HubApprovalVerdict
            switch event.keyCode {
            case UInt16(kVK_ANSI_Y): verdict = .allow
            case UInt16(kVK_ANSI_N): verdict = .deny
            case UInt16(kVK_ANSI_O):
                guard allowsAsk else { return event }
                verdict = .ask
            default:
                return event
            }
            if event.isARepeat { return nil }
            onVerdict(verdict)
            return nil
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        isolated deinit { stop() }
    }
}

#Preview("Approval inline") {
    HubDecisionPreview(kind: .showing)
}

#Preview("Queued") {
    HubDecisionPreview(kind: .queued)
}

#Preview("Reduce Motion") {
    HubDecisionPreview(kind: .reduced)
}

private struct HubDecisionPreview: View {
    enum Kind { case showing, queued, reduced }
    var kind: Kind
    @State private var reply: String

    init(kind: Kind) {
        self.kind = kind
        _reply = State(initialValue: kind == .reduced ? "Try the retry helper again" : "")
    }

    var body: some View {
        HubDecisionRow(
            request: HubDecisionRequest(
                tool: kind == .reduced ? "Edit file" : "Run command",
                highRisk: kind == .showing,
                command: kind == .reduced ? nil : "./migrate.sh --apply",
                diff: kind == .reduced ? Self.sampleDiff : nil,
                secondsLeft: kind == .queued ? nil : 12,
                allowsAsk: true
            ),
            queue: HubDecisionQueue(thisRowIsQueued: kind == .queued, count: 1),
            scope: kind == .queued ? .approval : .row,
            reply: $reply,
            answerKeysOn: true,
            reduceMotion: kind == .reduced
        )
        .padding(14)
        .frame(width: 420, alignment: .leading)
        .background(Theme.storm)
    }

    private static var sampleDiff: FileDiff? {
        FileDiff.from(tool: "Edit", input: .object([
            "file_path": .string("migrate.sh"),
            "old_string": .string("apply = false"),
            "new_string": .string("apply = true"),
        ]))
    }
}

#else

/// Linux stand-in for the row's contract. The SwiftUI row is the same statics when AppKit is present.
enum HubDecisionRow {
    static var accessibilityContractLabel: String { HubDecisionContract.accessibilityContractLabel }
    static func ownedAccessibilityLabels(showingApproval: Bool) -> [String] {
        HubDecisionContract.ownedAccessibilityLabels(showingApproval: showingApproval)
    }
    static var reduceMotionRequest: HubDecisionMotion { HubDecisionContract.reduceMotionRequest }
    static func motion(reduceMotion: Bool) -> HubDecisionMotion { HubDecisionContract.motion(reduceMotion: reduceMotion) }
    static func animates(reduceMotion: Bool) -> Bool { HubDecisionContract.animates(reduceMotion: reduceMotion) }
    static var denyIsDefaultAction: Bool { HubDecisionContract.denyIsDefaultAction }
    static var approveIsDefaultAction: Bool { HubDecisionContract.approveIsDefaultAction }
    static var sendIsDefaultAction: Bool { HubDecisionContract.sendIsDefaultAction }
    static var askIsButton: Bool { HubDecisionContract.askIsButton }
    static func countdown(_ seconds: Int) -> String { HubDecisionContract.countdown(seconds) }
    static func queuedHint(thisRowIsQueued: Bool, count: Int) -> String? {
        HubDecisionContract.queuedHint(thisRowIsQueued: thisRowIsQueued, count: count)
    }
}

#endif
