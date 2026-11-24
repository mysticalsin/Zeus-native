import Foundation
import ZeusCore
#if canImport(SwiftUI) && canImport(AppKit)
import AppKit
import Carbon.HIToolbox
import SwiftUI
#endif

/// Revision 3 of the inline decision row. VoiceOver walks Allow once, Allow for this session,
/// Deny, and Deny with note. Reduce Motion is zero offset and scale 1, and the countdown text stays.
/// Deny is never the default action. Command is not a shortcut.
enum HubDecisionRowTestHost {
    static let contract = "group header, row, Allow once, Allow for this session, Deny, Deny with note, transcript, reply, Send, Open"

    static func verify() {
        let label = HubDecisionRow.accessibilityContractLabel
        precondition(label == contract, "accessibility label \(label) does not match the revision 3 contract")
        precondition(HubDecisionRow.ownedAccessibilityLabels(showingApproval: true) == [
            "Allow once", "Allow for this session", "Deny", "Deny with note", "Reply", "Send",
        ])
        precondition(HubDecisionRow.ownedAccessibilityLabels(showingApproval: false) == ["Reply", "Send"])
        precondition(HubDecisionContract.destructiveHoldSeconds == 1.2)
        precondition(HubDecisionContract.undoSeconds == 2)
        precondition(HubDecisionContract.noteCharacterLimit == 280)
        precondition(HubDecisionContract.commandKeyIsShortcut == false)
        precondition(HubDecisionContract.keysActive(decisionShowing: false) == false)
        precondition(HubDecisionContract.keysActive(decisionShowing: true))
        precondition(HubDecisionContract.countdownAnimates(reduceMotion: true) == false)
        precondition(HubDecisionContract.countdownTextRemainsWhenReduced)
        precondition(HubDecisionContract.usesGradient == false)
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
    static let allowOnceTitle = "Allow once"
    static let allowForSessionTitle = "Allow for this session"
    static let denyTitle = "Deny"
    static let denyWithNoteTitle = "Deny with note"
    static let undoTitle = "Undo"
    /// ZB-UIUX-DECISION-001. The row itself had no identifier.
    static let rowIdentifier = "hub.decision.row"
    /// ZB-UIUX-A11Y-030 Accept and ZB-UIUX-A11Y-034 Approve are Allow once.
    static let allowOnceIdentifier = "hub.decision.allow-once"
    /// ZB-UIUX-A11Y-034. Allow for this session is the other approval.
    static let allowSessionIdentifier = "hub.decision.allow-session"
    /// ZB-UIUX-A11Y-033. Deny on the approval card.
    static let denyIdentifier = "hub.decision.deny"
    /// ZB-UIUX-A11Y-032. Deny when the details are hidden.
    static let denyHiddenIdentifier = "hub.decision.deny.hidden"
    /// Deny with note. Same finding family as the unlabeled Deny control, ZB-UIUX-A11Y-033.
    static let denyNoteIdentifier = "hub.decision.deny-note"
    static let undoIdentifier = "hub.decision.undo"
    static let noteIdentifier = "hub.decision.note"
    static let queueIdentifier = "hub.decision.queue"
    static let countdownIdentifier = "hub.decision.countdown"
    static let replyLabel = "Reply"
    static let sendTitle = "Send"
    static let hiddenDetails = "Details hidden (Settings > Privacy)"
    /// Destructive approval is a press of this many seconds. 1.199 does not approve.
    static let destructiveHoldSeconds = 1.2
    static let undoSeconds = 2
    static let noteCharacterLimit = 280
    /// Command is never a shortcut.
    static let commandKeyIsShortcut = false
    /// The decision row is monochrome. It does not paint a gradient.
    static let usesGradient = false

    static let revision3ContractLabel = "group header, row, Allow once, Allow for this session, Deny, Deny with note, transcript, reply, Send, Open"

    static var accessibilityContractLabel: String { revision3ContractLabel }

    static func ownedAccessibilityLabels(showingApproval: Bool) -> [String] {
        var labels: [String] = []
        if showingApproval {
            labels.append(allowOnceTitle)
            labels.append(allowForSessionTitle)
            labels.append(denyTitle)
            labels.append(denyWithNoteTitle)
        }
        labels.append(replyLabel)
        labels.append(sendTitle)
        return labels
    }

    static func keysActive(decisionShowing: Bool) -> Bool { decisionShowing }

    /// The countdown text stays. Reduce Motion does not animate it.
    static func countdownAnimates(reduceMotion: Bool) -> Bool { !reduceMotion }
    static let countdownTextRemainsWhenReduced = true

    static var reduceMotionRequest: HubDecisionMotion { motion(reduceMotion: true) }

    static func motion(reduceMotion: Bool) -> HubDecisionMotion {
        .request(reduceMotion: reduceMotion)
    }

    /// Reduce Motion changes in one frame. The height spring runs only when this is true.
    static func animates(reduceMotion: Bool) -> Bool { !reduceMotion }

    /// Deny is never the default action. Allow once is not either: Return is handled only while a decision is showing.
    static let denyIsDefaultAction = false
    static let approveIsDefaultAction = false
    static let sendIsDefaultAction = false

    /// Ask is the existing keyboard verdict. It is not a button.
    static let askIsButton = false

    static func countdown(_ seconds: Int) -> String {
        countdown(seconds, paused: false)
    }

    static func countdown(_ seconds: Int, paused: Bool) -> String {
        let body = "\(max(seconds, 0)) s left, then it's denied."
        return paused ? "Countdown paused. \(body)" : body
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
        answerKeysOn ? "Stops this once. Escape or 3." : "Stops this once."
    }

    static func approveHint(answerKeysOn: Bool, allowsAsk _: Bool) -> String {
        answerKeysOn ? "Lets this run once. Return." : "Lets this run once."
    }

    static func sessionHint(answerKeysOn: Bool) -> String {
        answerKeysOn ? "Lets this run until the session ends. 2." : "Lets this run until the session ends."
    }

    static func denyWithNoteHint(answerKeysOn: Bool) -> String {
        answerKeysOn ? "Stops this once and keeps a note. 4." : "Stops this once and keeps a note."
    }

    static func denyAllHint(answerKeysOn: Bool) -> String {
        answerKeysOn ? "Denies every decision in the queue. Shift-Escape." : "Denies every decision in the queue."
    }

    static func undoHint(answerKeysOn: Bool) -> String {
        answerKeysOn ? "Takes the decision back. U." : "Takes the decision back."
    }
}

#if canImport(SwiftUI) && canImport(AppKit)

/// Inline approval on a session row. Allow once, Allow for this session, Deny, and Deny with note.
/// Monochrome glass, the page spring, and no gradient. Ask is not a button.
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
    var countdownPaused: Bool
    var undoAvailable: Bool
    var onAction: (HubDecisionRowAction) -> Void
    var onSend: () -> Void
    @State private var note = ""

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
        countdownPaused: Bool = false,
        undoAvailable: Bool = false,
        onAction: @escaping (HubDecisionRowAction) -> Void = { _ in },
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
        self.countdownPaused = countdownPaused
        self.undoAvailable = undoAvailable
        self.onAction = onAction
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
        .accessibilityIdentifier("hub.decision.row") // ZB-UIUX-DECISION-001
        .accessibilityLabel(HubDecisionContract.revision3ContractLabel)
        .animation(rowAnimation, value: phase)
        .animation(rowAnimation, value: receipt)
        .transaction { transaction in
            if !animating { transaction.disablesAnimations = true }
        }
        .background {
            HubDecisionKeyMonitor(
                active: keysActive,
                destructive: request?.tier == "Destructive",
                undoAvailable: undoAvailable,
                note: cappedNote,
                onAction: onAction
            )
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

    /// ZB-UIUX-ESCAPE-001. Keys, including Escape, are live only while a decision is showing.
    private var keysActive: Bool { (phase == .showing || undoAvailable) && HubDecisionContract.keysActive(decisionShowing: phase == .showing || undoAvailable) }

    private var cappedNote: String {
        String(note.prefix(HubDecisionContract.noteCharacterLimit))
    }

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
                    .fill(Glass.hairline)
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
                            .font(Glass.numeral(18))
                            .foregroundStyle(Glass.secondary)
                            .contentTransition(Self.countdownAnimates(reduceMotion: reduced) ? .numericText() : .identity)
                            .animation(Self.countdownAnimates(reduceMotion: reduced) ? .linear(duration: 0.2) : nil, value: seconds)
                            .accessibilityLabel(HubDecisionContract.countdown(seconds, paused: countdownPaused))
                            .accessibilityIdentifier("hub.decision.countdown")
                            .accessibilitySortPriority(HubDecisionFocus.countdownPriority)
                    }
                    if undoAvailable {
                    glassButton(
                        title: HubDecisionContract.undoTitle,
                        hint: HubDecisionContract.undoHint(answerKeysOn: true),
                        filled: false,
                        hold: false
                    ) { onAction(.undo) }
                        .accessibilityIdentifier("hub.decision.undo")
                    }
                }
                if let hint = Self.queuedHint(thisRowIsQueued: queue.thisRowIsQueued, count: queue.count),
                   let spoken = HubDecisionContract.queuedAccessibilityLabel(thisRowIsQueued: queue.thisRowIsQueued, count: queue.count) {
                    Text(hint)
                        .font(Glass.caption)
                        .foregroundStyle(Glass.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(spoken)
                        .accessibilityIdentifier("hub.decision.queue")
                        .accessibilitySortPriority(HubDecisionFocus.queuePriority)
                }
            }
            .padding(.top, 8)
            .transition(rowTransition)
        }
    }

    private func toolLine(_ request: HubDecisionRequest) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(request.tier.uppercased())
                .font(Glass.eyebrow)
                .foregroundStyle(Glass.tertiary)
            Text(request.tool)
                .font(Glass.title)
                .foregroundStyle(Glass.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(request.tier). \(request.tool)")
        .accessibilitySortPriority(HubDecisionFocus.toolPriority)
    }

    @ViewBuilder
    private func decisionBody(_ request: HubDecisionRequest) -> some View {
        if detailsHidden {
            Text(HubDecisionContract.hiddenDetails)
                .font(Glass.body)
                .foregroundStyle(Glass.secondary)
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
                .foregroundStyle(Glass.text)
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Glass.fill, in: RoundedRectangle(cornerRadius: Glass.rowRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Glass.rowRadius, style: .continuous).strokeBorder(Glass.hairline, lineWidth: 1))
                .accessibilitySortPriority(HubDecisionFocus.bodyPriority)
        } else if let question = request.question, !question.isEmpty {
            Text(question)
                .font(Glass.body)
                .foregroundStyle(Glass.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(question)
                .accessibilitySortPriority(HubDecisionFocus.bodyPriority)
        }
    }

    private func buttonRow(_ request: HubDecisionRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                glassButton(
                    title: HubDecisionContract.allowOnceTitle,
                    hint: HubDecisionContract.approveHint(answerKeysOn: answerKeysOn, allowsAsk: false),
                    filled: true,
                    hold: request.tier == "Destructive"
                ) { onAction(.allowOnce) }
                    .accessibilityIdentifier("hub.decision.allow-once") // ZB-UIUX-A11Y-030 ZB-UIUX-A11Y-034
                glassButton(
                    title: HubDecisionContract.allowForSessionTitle,
                    hint: HubDecisionContract.sessionHint(answerKeysOn: answerKeysOn),
                    filled: false,
                    hold: request.tier == "Destructive"
                ) { onAction(.allowForThisSession) }
                    .accessibilityIdentifier("hub.decision.allow-session") // ZB-UIUX-A11Y-034
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if detailsHidden {
                    glassButton(
                        title: HubDecisionContract.denyTitle,
                        hint: HubDecisionContract.denyHint(answerKeysOn: answerKeysOn),
                        filled: false,
                        hold: false
                    ) { onAction(.deny) }
                        .accessibilityIdentifier("hub.decision.deny.hidden") // ZB-UIUX-A11Y-032
                } else {
                    glassButton(
                        title: HubDecisionContract.denyTitle,
                        hint: HubDecisionContract.denyHint(answerKeysOn: answerKeysOn),
                        filled: false,
                        hold: false
                    ) { onAction(.deny) }
                        .accessibilityIdentifier("hub.decision.deny") // ZB-UIUX-A11Y-033
                }
                glassButton(
                    title: HubDecisionContract.denyWithNoteTitle,
                    hint: HubDecisionContract.denyWithNoteHint(answerKeysOn: answerKeysOn),
                    filled: false,
                    hold: false
                ) { onAction(.denyWithNote(cappedNote)) }
                    .accessibilityIdentifier("hub.decision.deny-note") // ZB-UIUX-A11Y-033
                Spacer(minLength: 0)
            }
            NotchTextField(text: $note, placeholder: "Note", onSubmit: { onAction(.denyWithNote(cappedNote)) })
                .onChange(of: note) { _, new in
                    if new.count > HubDecisionContract.noteCharacterLimit {
                        note = String(new.prefix(HubDecisionContract.noteCharacterLimit))
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Glass.fill, in: Capsule())
                .overlay(Capsule().strokeBorder(Glass.hairline, lineWidth: 1))
                .accessibilityLabel(HubDecisionContract.denyWithNoteTitle)
                .accessibilityIdentifier("hub.decision.note")
                .accessibilityValue("\(cappedNote.count) of \(HubDecisionContract.noteCharacterLimit) characters")
        }
    }

    /// A monochrome glass control. Filled is white on the canvas. Nothing here is a gradient.
    /// Destructive approval holds for 1.2 seconds. A shorter press does not fire.
    @ViewBuilder
    private func glassButton(
        title: String,
        hint: String,
        filled: Bool,
        hold: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let label = Text(title)
            .font(Glass.font(12, .medium))
            .foregroundStyle(filled ? Glass.canvas : Glass.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(Capsule().fill(filled ? Glass.text : Glass.fillRaised))
            .overlay(Capsule().strokeBorder(Glass.hairline, lineWidth: 1))
        Group {
            if hold {
                label
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { action() }
                    .onLongPressGesture(minimumDuration: HubDecisionContract.destructiveHoldSeconds, perform: action)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.plain)
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint(hint)
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
                    Button(action: onSend) {
                        Text(HubDecisionContract.sendTitle)
                            .font(Glass.font(12, .medium))
                            .foregroundStyle(Glass.canvas)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 28)
                            .background(Capsule().fill(Glass.text))
                            .overlay(Capsule().strokeBorder(Glass.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .opacity(replyHasText ? 1 : 0.4)
                    .animation(animating ? .easeOut(duration: Motion.feedbackDuration) : nil, value: replyHasText)
                    .accessibilityLabel(HubDecisionContract.sendTitle)
                    .accessibilityHint(replyHasText ? "Sends the reply. Approval comes first." : "Type something first.")
                    .accessibilitySortPriority(HubDecisionFocus.priority(.send)),
                    isDefault: Self.sendIsDefaultAction)
            }
            if let receipt, !receipt.isEmpty {
                Text(receipt)
                    .font(Glass.caption)
                    .foregroundStyle(Glass.secondary)
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
    /// Low, High, or Destructive. Destructive approval is a 1.2 second hold.
    var tier: String
    var command: String?
    var question: String?
    var diff: FileDiff?
    var secondsLeft: Int?
    var allowsAsk: Bool

    init(tool: String, tier: String = "Low", command: String? = nil, question: String? = nil,
         diff: FileDiff? = nil, secondsLeft: Int? = nil, allowsAsk: Bool = false) {
        self.tool = tool
        self.tier = tier
        self.command = command
        self.question = question
        self.diff = diff
        self.secondsLeft = secondsLeft
        self.allowsAsk = allowsAsk
    }
}

/// What the row reports. The machine decides whether it runs.
enum HubDecisionRowAction: Equatable {
    case allowOnce
    case allowForThisSession
    case deny
    case denyWithNote(String)
    case denyAllQueued
    case undo
}

/// ZB-UIUX-ESCAPE-001. Escape and 3 deny. The monitor is installed only while a decision is showing.
/// Return allows once. 2 allows for this session. 4 denies with a note. Shift-Escape denies the queue. U undoes.
/// Command is not a shortcut. A repeat is swallowed.
private struct HubDecisionKeyMonitor: NSViewRepresentable {
    var active: Bool
    var destructive: Bool
    var undoAvailable: Bool
    var note: String
    var onAction: (HubDecisionRowAction) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.sync(active: active, destructive: destructive, undoAvailable: undoAvailable, note: note, onAction: onAction)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.sync(active: active, destructive: destructive, undoAvailable: undoAvailable, note: note, onAction: onAction)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        MainActor.assumeIsolated { coordinator.stop() }
    }

    @MainActor
    final class Coordinator {
        private var monitor: Any?
        private var destructive = false
        private var undoAvailable = false
        private var note = ""
        private var onAction: (HubDecisionRowAction) -> Void = { _ in }

        func sync(
            active: Bool,
            destructive: Bool,
            undoAvailable: Bool,
            note: String,
            onAction: @escaping (HubDecisionRowAction) -> Void
        ) {
            self.destructive = destructive
            self.undoAvailable = undoAvailable
            self.note = note
            self.onAction = onAction
            if active { start() } else { stop() }
        }

        private func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return MainActor.assumeIsolated { self.handle(event) }
            }
        }

        /// ZB-UIUX-ESCAPE-001. Escape denies. 3 denies too.
        private func handle(_ event: NSEvent) -> NSEvent? {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
            if flags.contains(.command) { return event }
            let shift = flags.contains(.shift)
            guard flags.subtracting(.shift).isEmpty else { return event }
            if event.isARepeat { return nil }
            if shift {
                guard event.keyCode == UInt16(kVK_Escape), undoAvailable == false else { return event }
                onAction(.denyAllQueued)
                return nil
            }
            switch event.keyCode {
            case UInt16(kVK_Escape), UInt16(kVK_ANSI_3):
                guard undoAvailable == false else { return event }
                onAction(.deny)
            case UInt16(kVK_Return):
                guard destructive == false, undoAvailable == false else { return event }
                onAction(.allowOnce)
            case UInt16(kVK_ANSI_2):
                guard destructive == false, undoAvailable == false else { return event }
                onAction(.allowForThisSession)
            case UInt16(kVK_ANSI_4):
                guard undoAvailable == false else { return event }
                onAction(.denyWithNote(note))
            case UInt16(kVK_ANSI_U):
                guard undoAvailable else { return event }
                onAction(.undo)
            default:
                return event
            }
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
                tier: kind == .showing ? "Destructive" : "Low",
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
