import Foundation

/// A request from the `zeus` CLI to the running app: one JSON line on the same Unix socket
/// that `zeus-hook` uses. `kind` tells it apart from agent hook events.
public struct ZeusCommand: Codable, Equatable, Sendable {
    public enum Op: String, Codable, Sendable, CaseIterable {
        case ask, listen, say, status, tasks, cancel, todo, browse, code, research, term, debug
    }

    public static let kindValue = "zeus.command"

    public var kind: String = ZeusCommand.kindValue
    public var v: Int = 1
    public let id: String
    public let op: Op
    public let text: String?
    /// More thinking for this turn (the brain runs with a higher effort).
    public let deep: Bool
    /// Speak the answer aloud as well as returning it.
    public let speak: Bool
    /// `listen` only: how long to listen.
    public let seconds: Double?
    /// `code` and `term`: the project to work in (`--in`), by name or path.
    public let project: String?
    /// `code`: which coding agent (`--tool claude|codex|gemini|cursor-agent`); nil is Tony's preferred one.
    public let tool: String?
    /// `browse` only: use the separate browser-use browser instead of Tony's Chrome (`--separate`).
    /// nil, not false, when off, so an older app reads the same line.
    public let separate: Bool?

    public init(id: String = UUID().uuidString, op: Op, text: String? = nil, deep: Bool = false,
                speak: Bool = true, seconds: Double? = nil, project: String? = nil, tool: String? = nil, separate: Bool = false) {
        self.id = id
        self.op = op
        self.text = text
        self.deep = deep
        self.speak = speak
        self.seconds = seconds
        self.project = project
        self.tool = tool
        self.separate = separate ? true : nil
    }

    /// True when a socket line is a CLI command rather than an agent hook event.
    public static func isCommand(_ line: Data) -> Bool {
        struct Probe: Decodable { let kind: String? }
        return (try? JSONDecoder().decode(Probe.self, from: line))?.kind == kindValue
    }
}

public struct ZeusTaskInfo: Codable, Equatable, Sendable {
    public let id: String
    public let op: String
    public let text: String
    public var state: String
    public let started: Date

    public init(id: String, op: String, text: String, state: String, started: Date) {
        self.id = id
        self.op = op
        self.text = text
        self.state = state
        self.started = started
    }
}

public struct ZeusCommandReply: Codable, Equatable, Sendable {
    public let id: String
    public let ok: Bool
    public var text: String
    public var actions: [String]
    public var problems: [String]
    public var tasks: [ZeusTaskInfo]
    public var status: [String: String]

    public init(id: String, ok: Bool, text: String, actions: [String] = [], problems: [String] = [],
                tasks: [ZeusTaskInfo] = [], status: [String: String] = [:]) {
        self.id = id
        self.ok = ok
        self.text = text
        self.actions = actions
        self.problems = problems
        self.tasks = tasks
        self.status = status
    }
}

public enum ZeusCLIError: Error, Equatable {
    case usage(String)

    public var message: String {
        switch self { case .usage(let text): text }
    }
}

public struct ZeusCLIInvocation: Equatable, Sendable {
    /// nil means print the help.
    public let command: ZeusCommand?
    public let json: Bool
    public let timeout: TimeInterval
}

/// Argument parsing and output for the `zeus` CLI, kept here so it is unit tested.
public enum ZeusCLI {
    public static let usage = """
    zeus: talk to ZEUS from the terminal. ZEUS must be running.

      zeus "open my zeus repo in Finder"   ask ZEUS to do something (same brain and actions as voice)
      zeus ask "<request>"                 the same, for requests that start with a command word
      zeus browse "<goal>" [--separate]    work through a website on its own in your Chrome, step by step
                                           (--separate: in the separate browser-use browser instead)
      zeus code "<task>" [--in <project>] [--tool codex]   start a coding agent in a terminal, in that project
      zeus research "<question>" [--deep]  search the web, speak a short answer, save the full report
      zeus term [<project>]                open a terminal (in that project)
      zeus listen [--seconds N]            start a voice turn now, as if the talk key were held (6 s)
      zeus say "<text>"                    speak text with ZEUS's current voice
      zeus status                          is ZEUS up, which brain and voice, what is running
      zeus tasks                           recent CLI tasks
      zeus cancel <id|all>                 cancel a running task
      zeus todo add "<to-do>"              add a to-do ("call Anna tomorrow" sets the due date)
      zeus todo list                       the open to-dos
      zeus todo done <n|words>             tick one off (number from the list, or words from it)
      zeus todo remove <n|words>           delete one
      zeus debug <subcommand>              internal test hooks (\(DebugSubcommandCatalog.list))
      zeus insomnia-guard [--verbose]      lid-closed backstop (launchd runs it): restores sleep if Zeus is gone

    Options: --json (raw reply), --deep (more thinking), --quiet (don't speak the answer)
    Exit codes: 0 ok, 1 ZEUS answered with a failure, 2 usage error, 3 ZEUS isn't running.
    """

    /// The longest `zeus listen --seconds` accepted (an hour); "inf" and huge values are refused.
    public static let maxListenSeconds: Double = 3600

    public static func parse(_ arguments: [String], id: String = UUID().uuidString) throws -> ZeusCLIInvocation {
        var json = false, deep = false, quiet = false, separate = false
        var seconds: Double?
        var project: String?, tool: String?
        var words: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--json": json = true
            case "--deep": deep = true
            case "--quiet", "-q": quiet = true
            case "--separate": separate = true
            case "--seconds":
                guard index + 1 < arguments.count, let value = Double(arguments[index + 1]),
                      value > 0, value.isFinite, value <= maxListenSeconds else {
                    throw ZeusCLIError.usage("--seconds needs a number of seconds, up to \(Int(maxListenSeconds))")
                }
                seconds = value
                index += 1
            case "--in", "--tool":
                guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                    throw ZeusCLIError.usage("\(argument) needs a value")
                }
                if argument == "--in" { project = arguments[index + 1] } else { tool = arguments[index + 1] }
                index += 1
            case "-h", "--help":
                return ZeusCLIInvocation(command: nil, json: json, timeout: 0)
            case "--":
                words += arguments[(index + 1)...]
                index = arguments.count
                continue
            default:
                if argument.hasPrefix("--") {
                    if words.first == "debug" || arguments.first == "debug" {
                        words.append(argument)
                    } else {
                        throw ZeusCLIError.usage("unknown option \(argument)")
                    }
                } else {
                    words.append(argument)
                }
            }
            index += 1
        }
        guard let first = words.first else { return ZeusCLIInvocation(command: nil, json: json, timeout: 0) }
        if first == "help" { return ZeusCLIInvocation(command: nil, json: json, timeout: 0) }

        let op: ZeusCommand.Op
        let rest: [String]
        if let named = ZeusCommand.Op(rawValue: first) {
            op = named
            rest = Array(words.dropFirst())
        } else {
            op = .ask
            rest = words
        }
        let text = rest.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        switch op {
        case .ask, .say:
            if text.isEmpty { throw ZeusCLIError.usage("\(op.rawValue) needs some text") }
        case .browse:
            if text.isEmpty { throw ZeusCLIError.usage("browse needs a goal, e.g. zeus browse \"find the cheapest USB-C cable on amazon.fr\"") }
        case .code:
            if text.isEmpty { throw ZeusCLIError.usage("code needs a task, e.g. zeus code \"fix the failing tests\" --in zeus") }
            if let tool, CodingTool.named(tool) == nil {
                throw ZeusCLIError.usage("--tool takes claude, codex, gemini or cursor-agent")
            }
        case .research:
            if text.isEmpty { throw ZeusCLIError.usage("research needs a question, e.g. zeus research \"how do solid-state batteries work\" --deep") }
        case .term:
            if project != nil, !text.isEmpty { throw ZeusCLIError.usage("term takes one project, either as an argument or with --in") }
        case .cancel:
            if text.isEmpty { throw ZeusCLIError.usage("cancel needs a task id (from zeus tasks) or all") }
        case .debug:
            if text.isEmpty { throw ZeusCLIError.usage("debug needs a subcommand, e.g. open-settings, onboarding, screenshot, tab, animate") }
        case .todo:
            let sub = rest.first ?? ""
            if sub == "add", rest.count < 2 { throw ZeusCLIError.usage("todo add needs the to-do text") }
            if !["add", "list", "done", "remove"].contains(sub) { throw ZeusCLIError.usage("todo takes add \"<text>\", list, done <n|words> or remove <n|words>") }
            if sub == "done" || sub == "remove", rest.count < 2 { throw ZeusCLIError.usage("todo \(sub) needs a number from zeus todo list or words from the title") }
            if sub == "list", rest.count > 1 { throw ZeusCLIError.usage("todo list takes no text") }
        case .status, .tasks, .listen:
            if !text.isEmpty { throw ZeusCLIError.usage("\(op.rawValue) takes no text") }
        }
        if separate, op != .browse { throw ZeusCLIError.usage("--separate only goes with browse") }
        let timeout: TimeInterval = switch op {
        case .ask: deep ? 300 : 150
        // Up to 25 steps, each a short brain call, plus time for Tony to approve risky steps.
        case .browse: 1_200
        case .listen: (seconds ?? 6) + 150
        // Opening a terminal is quick; research waits for the whole report.
        case .code, .term: 20
        case .research: deep ? 600 : 240
        case .debug: 30
        default: 10
        }
        // `zeus term zeus` names the project as the argument.
        if op == .term, project == nil, !text.isEmpty { project = text }
        let normalizedText: String? = {
            guard op == .debug, !text.isEmpty else { return text.isEmpty ? nil : text }
            return Self.normalizeDebugText(text)
        }()
        let command = ZeusCommand(id: id, op: op, text: op == .term ? nil : normalizedText, deep: deep,
                                  speak: !quiet, seconds: seconds, project: project,
                                  tool: tool.flatMap(CodingTool.named)?.rawValue, separate: separate)
        return ZeusCLIInvocation(command: command, json: json, timeout: timeout)
    }

    /// Makes WAV paths absolute at the CLI so the app receives a stable path (R24 dictate-file).
    static func normalizeDebugText(_ text: String) -> String {
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return text }
        let sub = parts[0].lowercased()
        guard sub == "dictate-file" || sub == "wake-file" else { return text }
        let path = DebugAudioPath.resolve(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
        return "\(parts[0]) \(path)"
    }

    public static func render(_ reply: ZeusCommandReply, op: ZeusCommand.Op) -> String {
        var lines: [String]
        switch op {
        case .status:
            lines = reply.status.keys.sorted().map { "\($0): \(reply.status[$0] ?? "")" }
        case .tasks:
            lines = [reply.text] + reply.tasks.map {
                "\($0.id.prefix(8))  \($0.state.padding(toLength: 10, withPad: " ", startingAt: 0))\($0.op)  \($0.text)"
            }
        default:
            lines = reply.text.isEmpty ? [] : [reply.text]
        }
        lines += reply.actions.map { "action: \($0)" }
        lines += reply.problems.map { "problem: \($0)" }
        return lines.joined(separator: "\n")
    }
}

/// Talk key gestures: hold to talk, or double-tap to latch listening on until the next tap.
/// Pure state so it is unit tested; HotkeyMonitor feeds it key down/up times.
public struct TalkKeyLatch: Sendable {
    public enum Action: Equatable, Sendable {
        case start
        case stop
        /// A quick tap: stop after `gap` unless a second tap comes first.
        case stopLater(TimeInterval)
        case cancelPendingStop
    }

    private enum State: Equatable, Sendable {
        case idle
        case holding(down: TimeInterval, second: Bool)
        case tapped(up: TimeInterval)
        case latched
        case ending
    }

    public var tapMax: TimeInterval = 0.3
    public var doubleTapGap: TimeInterval = 0.4
    private var state: State = .idle

    public init() {}

    public var isLatched: Bool { state == .latched }

    public mutating func keyDown(at time: TimeInterval) -> Action? {
        switch state {
        case .idle:
            state = .holding(down: time, second: false)
            return .start
        case .tapped(let up):
            state = .holding(down: time, second: time - up <= doubleTapGap)
            return .cancelPendingStop
        case .latched:
            state = .ending
            return .stop
        case .holding, .ending:
            return nil
        }
    }

    public mutating func keyUp(at time: TimeInterval) -> Action? {
        switch state {
        case .holding(let down, let second):
            let quick = time - down <= tapMax
            if second, quick {
                state = .latched
                return nil
            }
            if !second, quick {
                state = .tapped(up: time)
                return .stopLater(doubleTapGap)
            }
            state = .idle
            return .stop
        case .ending:
            state = .idle
            return nil
        case .idle, .tapped, .latched:
            return nil
        }
    }

    /// The `stopLater` timer fired with no second tap.
    public mutating func pendingStopFired() -> Action? {
        guard case .tapped = state else { return nil }
        state = .idle
        return .stop
    }

    /// Escape while holding or latched (O1): end with nothing sent.
    public mutating func cancelFromEsc() -> Bool {
        guard state != .idle else { return false }
        state = .idle
        return true
    }
}
