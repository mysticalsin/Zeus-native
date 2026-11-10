import AppKit
import Observation
import SwiftUI
import ZeusCore

// MARK: Settings

@MainActor
@Observable
final class AgentSettings {
    static let shared = AgentSettings()
    private let defaults = UserDefaults.standard

    /// Hold completion cards and peeks while a full-screen app is in front.
    var quietInFullScreen: Bool { didSet { defaults.set(quietInFullScreen, forKey: "agents.quietFullScreen") } }
    var completionSound: Bool { didSet { defaults.set(completionSound, forKey: "agents.completionSound") } }
    var completionCards: Bool { didSet { defaults.set(completionCards, forKey: "agents.completionCards") } }

    private init() {
        quietInFullScreen = defaults.object(forKey: "agents.quietFullScreen") as? Bool ?? true
        completionSound = defaults.object(forKey: "agents.completionSound") as? Bool ?? true
        completionCards = defaults.object(forKey: "agents.completionCards") as? Bool ?? true
    }
}

/// Settings › General › Agents.
struct AgentSettingsSection: View {
    let settings = AgentSettings.shared
    let answers = QuestionAnswers.shared

    var body: some View {
        Section("Agents") {
            Toggle("Show a card when an agent finishes", isOn: Binding(get: { settings.completionCards }, set: { settings.completionCards = $0 }))
            Toggle("Play a sound when an agent finishes", isOn: Binding(get: { settings.completionSound }, set: { settings.completionSound = $0 }))
            Toggle("Stay quiet while an app is full screen", isOn: Binding(get: { settings.quietInFullScreen }, set: { settings.quietInFullScreen = $0 }))
            Text("In full screen only questions and approvals appear, without sound, because the agent is waiting on them.")
                .font(.callout).foregroundStyle(.secondary)
            LabeledContent("Question answers") {
                HStack {
                    Text(answers.tracker.path == .allowWithAnswers ? "Filled into the question" : "Sent as a message")
                        .foregroundStyle(.secondary)
                    if answers.tracker.path == .denyWithAnswer {
                        Button("Try Again") { answers.reset() }
                            .help("Try filling answers into the question again, e.g. after updating Claude Code.")
                    }
                }
            }
        }
        OtherAgentsSection()
    }
}

// MARK: Question answers

/// Remembers which answer path Claude Code honours on this Mac (see `QuestionAnswerTracker`).
@MainActor
@Observable
final class QuestionAnswers {
    static let shared = QuestionAnswers()
    private(set) var tracker: QuestionAnswerTracker

    private init() {
        let saved = UserDefaults.standard.string(forKey: "agents.answerPath").flatMap(QuestionAnswerPath.init(rawValue:))
        tracker = QuestionAnswerTracker(path: saved ?? .allowWithAnswers)
    }

    func decision(id: String, session: String, input: JSONValue?, answers: [String: [String]]) -> HookDecision {
        let decision = tracker.path.decision(id: id, input: input, answers: answers)
        tracker.sent(session: session, answers: answers)
        return decision
    }

    func toolResult(session: String, text: String?) {
        tracker.toolResult(session: session, text: text)
        save()
    }

    func waitingForInput(session: String) -> Bool {
        let fellBack = tracker.waitingForInput(session: session)
        save()
        return fellBack
    }

    func reset() {
        tracker.reset()
        save()
    }

    private func save() { UserDefaults.standard.set(tracker.path.rawValue, forKey: "agents.answerPath") }
}

// MARK: Terminals and full screen

/// The terminal each agent session runs in, so cards can jump back to it.
@MainActor
final class AgentTerminals {
    static let shared = AgentTerminals()
    private var bySession: [String: TerminalInfo] = [:]

    func remember(_ info: TerminalInfo?, for session: String) {
        if let info { bySession[session] = info }
    }

    func forget(_ session: String) { bySession[session] = nil }

    func info(for session: String) -> TerminalInfo? { bySession[session] }

    func canJump(to session: String?) -> Bool {
        session.flatMap { bySession[$0]?.targetBundleID } != nil
    }

    /// Brings the session's terminal or editor forward, on the exact tab in Terminal and
    /// iTerm2 (macOS asks once to let ZEUS control them). Returns false when it is unknown.
    @discardableResult
    func jump(to session: String?) -> Bool {
        guard let session, let info = bySession[session], let bundleID = info.targetBundleID else { return false }
        if let source = TerminalTabScript.script(for: info),
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first != nil {
            var error: NSDictionary?
            if NSAppleScript(source: source)?.executeAndReturnError(&error).booleanValue == true { return true }
        }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return app.activate()
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
}

enum FullScreenDetector {
    /// True when the frontmost app has a normal window covering a whole display (a full-screen
    /// space, a game, a slideshow). Window bounds need no Screen Recording permission.
    static func frontAppIsFullScreen() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let screens = NSScreen.screens.map(\.frame.size)
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"] else { return false }
            return screens.contains { abs($0.width - width) < 1 && abs($0.height - height) < 1 }
        }
    }
}

// MARK: Approval detail (plan, question, diff)

/// Extra content for an approval card, plus what the person chose in it.
@MainActor
@Observable
final class ApprovalDetail {
    enum Kind {
        case plan(String)
        case questions([AgentQuestion])
        case diff(FileDiff)
    }

    let kind: Kind
    let session: String?
    /// Chosen option labels per question.
    var choices: [String: [String]] = [:]
    /// Set before resolving with "allow": the tool input Claude should run with.
    var updatedInput: JSONValue?
    /// Set before resolving with "deny": what Claude reads.
    var denyMessage: String?
    let input: JSONValue?
    /// True once the person answered the questions in the card.
    private(set) var answered = false

    init(kind: Kind, input: JSONValue?, session: String?) {
        self.kind = kind
        self.input = input
        self.session = session
    }

    /// For tools that get a richer card; nil keeps the plain command card.
    static func make(tool: String?, input: JSONValue?, session: String?) -> ApprovalDetail? {
        switch tool {
        case "ExitPlanMode":
            return AgentPlan.text(input).map { ApprovalDetail(kind: .plan($0), input: input, session: session) }
        case "AskUserQuestion":
            let questions = AgentQuestion.parse(input)
            return questions.isEmpty ? nil : ApprovalDetail(kind: .questions(questions), input: input, session: session)
        default:
            return FileDiff.from(tool: tool, input: input).map { ApprovalDetail(kind: .diff($0), input: input, session: session) }
        }
    }

    /// Plans and questions bring their own buttons; diffs keep Approve / Deny.
    var hasOwnActions: Bool {
        if case .diff = kind { return false }
        return true
    }

    /// Extra height the card needs, so the notch window grows to fit.
    var height: CGFloat {
        switch kind {
        case .plan: 150 + 40
        case .questions(let questions):
            min(questions.reduce(0) { $0 + 22 + CGFloat($1.options.count) * 30 } + 40, 300)
        case .diff(let diff): 24 + CGFloat(diff.lines.count) * 15 + (diff.hiddenLines > 0 ? 14 : 0)
        }
    }

    var announcement: String {
        switch kind {
        case .plan: "has a plan ready for review"
        case .questions(let questions): "asks: \(questions.first?.question ?? "a question")"
        case .diff(let diff): "wants to edit \(diff.fileName)"
        }
    }

    func toggle(_ label: String, in question: AgentQuestion) {
        var picked = choices[question.question] ?? []
        if question.multiSelect {
            if let index = picked.firstIndex(of: label) { picked.remove(at: index) } else { picked.append(label) }
        } else {
            picked = [label]
        }
        choices[question.question] = picked
    }

    func isComplete(_ questions: [AgentQuestion]) -> Bool {
        questions.allSatisfy { !(choices[$0.question] ?? []).isEmpty }
    }

    func answer(_ resolve: (HookDecision.Verdict) -> Void) {
        updatedInput = AgentQuestion.answeredInput(input, answers: choices)
        answered = true
        resolve(.allow)
    }
}

/// The plan, question or diff section inside the notch approval card.
struct ApprovalDetailView: View {
    let detail: ApprovalDetail
    let agent: String
    let resolve: (HookDecision.Verdict) -> Void

    var body: some View {
        switch detail.kind {
        case .plan(let plan): planView(plan)
        case .questions(let questions): questionsView(questions)
        case .diff(let diff): DiffPreview(diff: diff)
        }
    }

    private func planView(_ plan: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PageScroll(.vertical) {
                MarkdownBlocksView(text: plan, size: 11.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 150)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel("Plan")
            HStack(spacing: 8) {
                terminalButton(title: "Edit in Terminal")
                Spacer()
                CardButton(title: "Keep Planning", tint: Theme.cloudSecondary, filled: false) {
                    detail.denyMessage = AgentPlan.feedbackMessage("")
                    resolve(.deny)
                }
                .accessibilityHint("Sends the plan back to \(agent) to keep working on it.")
                CardButton(title: "Approve Plan", tint: Theme.leaf, filled: true) { resolve(.allow) }
                    .accessibilityHint("Lets \(agent) start on this plan.")
            }
        }
    }

    private func questionsView(_ questions: [AgentQuestion]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PageScroll(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(questions, id: \.question) { question in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(question.question)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.cloudPrimary)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(question.options, id: \.label) { option in
                                optionRow(option, in: question, single: questions.count == 1 && !question.multiSelect)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 250)
            HStack(spacing: 8) {
                terminalButton(title: "Answer in Terminal")
                Spacer()
                if questions.count > 1 || questions.contains(where: \.multiSelect) {
                    CardButton(title: "Send Answers", tint: Theme.accent, filled: true) { detail.answer(resolve) }
                        .disabled(!detail.isComplete(questions))
                        .opacity(detail.isComplete(questions) ? 1 : 0.5)
                }
            }
        }
    }

    private func optionRow(_ option: AgentQuestion.Option, in question: AgentQuestion, single: Bool) -> some View {
        let picked = detail.choices[question.question]?.contains(option.label) == true
        return Button {
            detail.toggle(option.label, in: question)
            // One question, one choice: picking it is the answer.
            if single { detail.answer(resolve) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: question.multiSelect ? (picked ? "checkmark.square.fill" : "square") : (picked ? "largecircle.fill.circle" : "circle"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(picked ? Theme.accent : Theme.cloudQuiet)
                VStack(alignment: .leading, spacing: 0) {
                    Text(option.label).font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(Theme.cloudPrimary)
                    if let detail = option.detail {
                        Text(detail).font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 26)
            .background(Color.white.opacity(picked ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(option.detail.map { "\(option.label), \($0)" } ?? option.label)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    @ViewBuilder
    private func terminalButton(title: String) -> some View {
        // "ask" leaves the decision to the terminal's own prompt, where you can type. With no known
        // terminal there is nowhere to answer, so the button is absent and a failed jump keeps the card.
        if AgentTerminals.shared.canJump(to: detail.session) {
            CardButton(title: title, tint: Theme.cloudSecondary, filled: false) {
                if AgentTerminals.shared.jump(to: detail.session) { resolve(.ask) }
            }
            .accessibilityHint("Brings the terminal forward and answers there.")
        }
    }
}

/// A few lines of a file edit, coloured like a review diff.
struct DiffPreview: View {
    let diff: FileDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: diff.isNewFile ? "doc.badge.plus" : "doc.text").font(.system(size: 10, weight: .semibold))
                Text(diff.fileName).font(.system(size: 11, weight: .semibold, design: .monospaced)).lineLimit(1)
                Spacer()
                Text("+\(diff.added)").foregroundStyle(Theme.leaf)
                Text("−\(diff.removed)").foregroundStyle(Theme.danger)
            }
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.cloudSecondary)
            .frame(height: 20)
            ForEach(Array(diff.lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 6) {
                    Text(symbol(line.kind)).frame(width: 8)
                    Text(line.text.isEmpty ? " " : line.text).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(color(line.kind))
                .frame(height: 15)
                .background(background(line.kind))
            }
            if diff.hiddenLines > 0 {
                Text("\(diff.hiddenLines) more lines").font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.cloudQuiet).frame(height: 14)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Edit to \(diff.fileName): \(diff.added) lines added, \(diff.removed) removed")
    }

    private func symbol(_ kind: FileDiff.Kind) -> String {
        switch kind { case .added: "+"; case .removed: "−"; case .context: " " }
    }

    private func color(_ kind: FileDiff.Kind) -> Color {
        switch kind { case .added: Theme.leaf; case .removed: Theme.danger; case .context: Theme.cloudQuiet }
    }

    private func background(_ kind: FileDiff.Kind) -> Color {
        switch kind { case .added: Theme.leaf.opacity(0.1); case .removed: Theme.danger.opacity(0.1); case .context: .clear }
    }
}

// MARK: Shared card grammar

/// The one status vocabulary the in-notch agent cards share: completion, approval, question,
/// failure, quiet agent and the welcome-back rows.
enum AgentCardKind: Equatable {
    case done, needsYou, question, failed, quiet

    var label: String {
        switch self {
        case .done: "Done"
        case .needsYou: "Needs you"
        case .question: "Question"
        case .failed: "Failed"
        case .quiet: "Quiet"
        }
    }

    var tint: Color {
        switch self {
        case .done: Theme.leaf
        case .needsYou: Theme.ember
        case .question: Theme.accent
        case .failed: Theme.danger
        case .quiet: Theme.amber
        }
    }

    var symbol: String {
        switch self {
        case .done: "checkmark"
        case .needsYou: "hand.raised.fill"
        case .question: "questionmark"
        case .failed: "exclamationmark"
        case .quiet: "moon.zzz.fill"
        }
    }

    /// Done and failed agents rest, a quiet one nods off, one that waits on you looks alert.
    var avatarState: BotAvatarState {
        switch self {
        case .done, .failed: .forActivity(running: false, idleFor: 0)
        case .needsYou, .question: .forActivity(running: true, idleFor: 0)
        case .quiet: .forActivity(running: false, idleFor: 600)
        }
    }

    /// The chip for a session row; working and idle sessions have none.
    static func kind(for status: NotchModel.Status) -> AgentCardKind? {
        switch status {
        case .done: .done
        case .needsYou: .needsYou
        case .failed: .failed
        case .stalled: .quiet
        case .idle, .working: nil
        }
    }
}

/// Small status capsule: glyph and word in the card's tint.
struct AgentStatusChip: View {
    let kind: AgentCardKind

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: kind.symbol).font(.system(size: 8.5, weight: .bold))
            Text(kind.label).font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(kind.tint)
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(Capsule().fill(kind.tint.opacity(0.16)))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.label)
    }
}

/// The round close button every peek card ends with.
struct AgentCardDismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.cloudQuiet)
                .frame(width: 22, height: 22).contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Dismiss")
    }
}

/// One peek card: bot avatar, agent and project, status chip and time on the first line, one line
/// of summary under them, and the card's own action (the primary, filled) before the close button.
/// Project and summary give way to a placeholder while details are hidden (Settings > Privacy).
struct AgentCardLayout<Actions: View>: View {
    static var height: CGFloat { 58 }

    let agent: String
    let project: String
    let kind: AgentCardKind
    let summary: String
    let time: String?
    let spokenTime: String?
    let dismiss: () -> Void
    let actions: Actions

    init(agent: String, project: String, kind: AgentCardKind, summary: String, time: String? = nil, spokenTime: String? = nil,
         dismiss: @escaping () -> Void, @ViewBuilder actions: () -> Actions) {
        self.agent = agent
        self.project = project
        self.kind = kind
        self.summary = summary
        self.time = time
        self.spokenTime = spokenTime
        self.dismiss = dismiss
        self.actions = actions()
    }

    private var hidden: Bool { MeetingState.hideDetails }
    private var shownSummary: String { hidden ? "Details hidden (Settings > Privacy)" : summary }

    private var spoken: String {
        var parts = ["\(agent), \(kind.label)"]
        if !hidden, !project.isEmpty { parts.append(project) }
        if let spokenTime { parts.append(spokenTime) }
        if !hidden { parts.append(summary) }
        return parts.joined(separator: ". ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            BotAvatarView.forAgent(agent, state: kind.avatarState, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(agent)
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.cloudPrimary)
                        .lineLimit(1).layoutPriority(2)
                    if !hidden, !project.isEmpty {
                        Text(project)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(Theme.cloudQuiet)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    AgentStatusChip(kind: kind)
                    if let time {
                        Text(time)
                            .font(.system(size: 10.5, design: .rounded).monospacedDigit()).foregroundStyle(Theme.cloudQuiet)
                            .lineLimit(1).fixedSize()
                    }
                }
                Text(shownSummary)
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.cloudSecondary)
                    .lineLimit(1).truncationMode(.tail)
                    .help(shownSummary)
            }
            actions
            AgentCardDismissButton(action: dismiss)
        }
        .padding(.horizontal, 2)
        .frame(minHeight: Self.height - 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spoken)
    }
}

// MARK: Completion card

/// "Done" card in the peek: what the agent said last, how long it took, and a way back to it.
struct CompletionCardView: View {
    let completion: AgentCompletion
    let dismiss: () -> Void

    var body: some View {
        AgentCardLayout(agent: completion.agent, project: completion.project, kind: .done, summary: completion.summary,
                        time: completion.duration.map(AgentCompletion.durationText),
                        spokenTime: completion.duration.map { "took \(AgentCompletion.durationText($0))" },
                        dismiss: dismiss) {
            if AgentTerminals.shared.canJump(to: completion.sessionID) {
                CardButton(title: "Open", tint: AgentCardKind.done.tint, filled: true) {
                    AgentTerminals.shared.jump(to: completion.sessionID)
                    dismiss()
                }
                .accessibilityHint("Brings \(completion.agent)'s terminal forward.")
            }
        }
    }

    static var height: CGFloat { AgentCardLayout<EmptyView>.height }
}

/// Small "open the terminal" glyph on agent rows; hidden when the terminal is unknown.
struct JumpToTerminalButton: View {
    let session: String
    let agent: String

    var body: some View {
        if AgentTerminals.shared.canJump(to: session) {
            GlyphButton(symbol: "arrow.up.forward.app", size: 11, tint: Theme.cloudSecondary, label: "Open \(agent)'s terminal") {
                AgentTerminals.shared.jump(to: session)
            }
        }
    }
}

/// Pill button in the notch's style.
struct CardButton: View {
    let title: String
    let tint: Color
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(filled ? Theme.storm : tint)
                .padding(.horizontal, 12)
                .frame(minHeight: 26)
                .background(Capsule().fill(filled ? tint : Color.white.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}
