import Foundation

public enum ApprovalCardKey: Equatable, Sendable {
    case allow, deny, open, jump, previous, next, allowChat
}

public enum ApprovalCardPhase: Equatable, Sendable {
    case asking, allowed, denied, timedOut
}

public enum ApprovalAllowStep: Equatable, Sendable {
    case idle, confirm, done
}

public enum ApprovalMotion: Equatable, Sendable {
    case slide, fade
}

public enum ApprovalCard {
    public static let quietInterval: TimeInterval = 0.4
    public static let collapsedLines = 6
    public static let holdDuration = 0.8
    public static let denyAllTitle = "Deny all"

    public struct Input: Equatable, Sendable {
        public var tool: String
        public var command: String
        public var file: String?
        public var added: Int?
        public var removed: Int?
        public var host: String?
        public var why: String?
        public var sessionTitle: String
        public var agent: String
        public var project: String
        public var risk: HookEvent.Risk
        public var reasons: [String]
        public var queueIndex: Int
        public var queueCount: Int
        public var modifiersHeld: Bool
        public var expanded: Bool
        public var holdElapsed: Double
        public var reduceMotion: Bool
        public var phase: ApprovalCardPhase

        public init(tool: String, command: String, file: String?, added: Int?, removed: Int?, host: String?,
                    why: String?, sessionTitle: String, agent: String, project: String, risk: HookEvent.Risk,
                    reasons: [String], queueIndex: Int, queueCount: Int, modifiersHeld: Bool, expanded: Bool,
                    holdElapsed: Double, reduceMotion: Bool, phase: ApprovalCardPhase) {
            self.tool = tool
            self.command = command
            self.file = file
            self.added = added
            self.removed = removed
            self.host = host
            self.why = why
            self.sessionTitle = sessionTitle
            self.agent = agent
            self.project = project
            self.risk = risk
            self.reasons = reasons
            self.queueIndex = queueIndex
            self.queueCount = queueCount
            self.modifiersHeld = modifiersHeld
            self.expanded = expanded
            self.holdElapsed = holdElapsed
            self.reduceMotion = reduceMotion
            self.phase = phase
        }
    }

    public struct Model: Equatable, Sendable {
        public var headline: String
        public var command: String
        public var canExpand: Bool
        public var why: String?
        public var header: String
        public var highRisk: Bool
        public var reasons: [String]
        public var statusChip: String?
        public var countdown: String?
        public var position: String
        public var showsNextEdge: Bool
        public var keycaps: Bool
        public var allowChat: Bool
        public var holdFraction: Double
        public var twoStep: Bool
        public var motion: ApprovalMotion
        public var phase: ApprovalCardPhase
    }

    public static func inputOpen(now: Date, appearedAt: Date) -> Bool {
        // Compare the dates. Subtracting them can land a hair under the 0.4 s quiet interval.
        now >= appearedAt.addingTimeInterval(quietInterval)
    }

    public static func key(letter: String, risk: HookEvent.Risk) -> ApprovalCardKey? {
        switch letter.uppercased() {
        case "Y": .allow
        case "N": .deny
        case "O": .open
        case "J": .jump
        case "A": risk == .high ? nil : .allowChat
        default: nil
        }
    }

    public static func arrow(_ direction: Int) -> ApprovalCardKey {
        direction < 0 ? .previous : .next
    }

    public static func keycap(_ key: ApprovalCardKey, risk: HookEvent.Risk, modifiersHeld: Bool) -> String? {
        guard modifiersHeld else { return nil }
        switch key {
        case .allow: return "Y"
        case .deny: return "N"
        case .open: return "O"
        case .jump: return "J"
        case .previous: return "←"
        case .next: return "→"
        case .allowChat: return risk == .high ? nil : "A"
        }
    }

    public static func headline(tool: String, command: String, file: String?, added: Int?, removed: Int?, host: String?) -> String {
        switch tool.lowercased() {
        case "bash", "shell", "run":
            let summary = command.split(whereSeparator: \.isWhitespace).prefix(8).joined(separator: " ")
            return "Run \(summary)"
        case "edit", "multiedit":
            let name = file ?? command
            if let added, let removed { return "Edit \(name) +\(added) −\(removed)" }
            return "Edit \(name)"
        case "write":
            return "Write \(file ?? command)"
        case "read":
            return "Read \(file ?? command)"
        case "webfetch", "fetch":
            return "Fetch \(host ?? command)"
        default:
            return command.isEmpty ? tool : "\(tool) \(command)"
        }
    }

    public static func commandBlock(_ command: String, expanded: Bool) -> (text: String, canExpand: Bool) {
        let lines = command.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let canExpand = lines.count > collapsedLines
        if expanded || !canExpand { return (command, canExpand) }
        return (lines.prefix(collapsedLines).joined(separator: "\n"), true)
    }

    public static func position(index: Int, count: Int) -> String {
        guard count > 0 else { return "" }
        return "\(index + 1) of \(count)"
    }

    public static func showsNextEdge(count: Int) -> Bool { count > 1 }

    public static func step(index: Int, count: Int, by: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + by, 0), count - 1)
    }

    public static func flash(allowed: Bool) -> String { allowed ? "Allowed" : "Denied" }

    public static func timeout(risk: HookEvent.Risk) -> String {
        risk == .high ? "Denied (timed out)" : "Handed back to terminal"
    }

    public static func holdFraction(elapsed: Double) -> Double {
        guard holdDuration > 0 else { return 0 }
        return min(max(elapsed / holdDuration, 0), 1)
    }

    public static func motion(reduceMotion: Bool) -> ApprovalMotion { reduceMotion ? .fade : .slide }

    public static func usesTwoStep(risk: HookEvent.Risk, reduceMotion: Bool) -> Bool {
        risk == .high && reduceMotion
    }

    public static func nextAllowStep(_ step: ApprovalAllowStep, risk: HookEvent.Risk, reduceMotion: Bool) -> ApprovalAllowStep {
        guard usesTwoStep(risk: risk, reduceMotion: reduceMotion) else { return .done }
        return step == .confirm ? .done : .confirm
    }

    /// Allow and Deny stay on the card for every arrival. A high-risk Allow is still a hold, and it is still labelled Allow.
    public struct Buttons: Equatable, Sendable {
        public var allow: String
        public var deny: String
        public var allowHolds: Bool
    }

    public static func buttons(risk: HookEvent.Risk, detailsHidden: Bool, detailHasOwnActions: Bool) -> Buttons {
        _ = detailsHidden
        _ = detailHasOwnActions
        return Buttons(allow: "Allow", deny: "Deny", allowHolds: risk == .high)
    }

    /// The command, tool and file stay visible unless the Mac is locked or the screen is being shared.
    public static func showsCommand(locked: Bool, screenShared: Bool) -> Bool {
        !locked && !screenShared
    }

    public static func hiddenReason(locked: Bool, screenShared: Bool) -> String? {
        if locked { return "Hidden while the Mac is locked." }
        if screenShared { return "Hidden while the screen is shared." }
        return nil
    }

    /// Once the countdown has ended, the card is no longer on the notch.
    public static func stillShown(now: Date, deadline: Date?) -> Bool {
        guard let deadline else { return true }
        return now < deadline
    }

    public static func announcement(risk: HookEvent.Risk, position: String, outcome: String?) -> String {
        var parts = [risk == .high ? "High risk" : "Request"]
        if !position.isEmpty { parts.append(position) }
        if let outcome, !outcome.isEmpty { parts.append(outcome) }
        return parts.joined(separator: ", ")
    }

    public static func make(_ input: Input) -> Model {
        let block = commandBlock(input.command, expanded: input.expanded)
        let why = input.why?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = input.sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let header = [title, input.agent, input.project].filter { !$0.isEmpty }.joined(separator: " · ")
        return Model(
            headline: headline(tool: input.tool, command: input.command, file: input.file, added: input.added, removed: input.removed, host: input.host),
            command: block.text,
            canExpand: block.canExpand,
            why: (why?.isEmpty == false) ? why : nil,
            header: header,
            highRisk: input.risk == .high,
            reasons: input.risk == .high ? input.reasons : [],
            statusChip: nil,
            countdown: nil,
            position: position(index: input.queueIndex, count: input.queueCount),
            showsNextEdge: showsNextEdge(count: input.queueCount),
            keycaps: input.modifiersHeld,
            allowChat: input.risk != .high,
            holdFraction: input.risk == .high && !input.reduceMotion ? holdFraction(elapsed: input.holdElapsed) : 0,
            twoStep: usesTwoStep(risk: input.risk, reduceMotion: input.reduceMotion),
            motion: motion(reduceMotion: input.reduceMotion),
            phase: input.phase)
    }
}
