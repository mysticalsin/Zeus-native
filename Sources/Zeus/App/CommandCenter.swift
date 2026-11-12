import Foundation
import ZeusCore

/// Which CLI commands may use the microphone, screen, input or launch agents, and whether the user
/// allowed that (Settings ▸ Privacy, off by default). Read-only commands never need the setting.
enum CLIAccess {
    static let defaultsKey = "cli.sensitiveCommands.enabled"

    static let refusal = "Refused: this command can use the microphone, screen or input, or launch agents. Turn on 'Allow command-line control' in Zeus Settings ▸ Privacy to allow it."

    static var enabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    /// True inside a CLI-originated turn while 'Allow command-line control' is off. Task-locals flow into
    /// child tasks, so capture and action boundaries anywhere in the turn can refuse to run.
    @TaskLocal static var turnRestricted = false

    /// Words that only make sense with the screen or with input: refused up front for restricted asks.
    static func restrictedAskRefusal(_ text: String) -> String? {
        ScreenAwareness.isScreenQuestion(text) ? refusal : nil
    }

    /// Debug hooks that capture, inject input, change privacy settings, write files or import keys.
    private static let sensitiveDebug: Set<String> = [
        "dictate-file", "wake-file", "record", "hands", "hands-live", "selection", "on-device-speech",
        "import-assistant-key", "engine-logos",
    ]
    /// The subset that starts capturing audio or screen content.
    private static let capturingDebug: Set<String> = ["dictate-file", "wake-file", "record", "on-device-speech"]

    static func isSensitive(op: ZeusCommand.Op, debugSubcommand: String, argument: String) -> Bool {
        switch op {
        case .listen, .browse, .code, .term: return true
        case .debug:
            if debugSubcommand == "screen-share" { return argument.lowercased() != "state" }
            return sensitiveDebug.contains(debugSubcommand)
        default: return false
        }
    }

    static func startsCapture(op: ZeusCommand.Op, debugSubcommand: String) -> Bool {
        op == .listen || (op == .debug && capturingDebug.contains(debugSubcommand))
    }
}

/// Serves the `zeus` CLI over the agent socket: typed and spoken turns (same brain, tags,
/// actions and notch approvals as the talk key), speech, status and a short task list.
@MainActor
final class CommandCenter {
    private struct Entry {
        var info: ZeusTaskInfo
        let turn: UUID
        var task: Task<TurnResult, Never>?
    }

    private let voice: VoiceTurnController
    private var entries: [Entry] = []
    /// Tokens of in-flight capture commands (the cue lifetime is the lifetime of this set).
    private var activeCaptures: Set<UUID> = []

    var onDebugOpenSettings: ((String?) -> Bool)?
    var onDebugOnboarding: ((Bool) -> Void)?
    var onDebugScreenshot: ((String?) async -> [String])?
    var onDebugTab: ((String) -> Bool)?
    var onDebugAnimate: ((String) -> Bool)?
    var onDebugHUDState: (() -> String)?
    /// `on`/`off`/`state`: P0 item I ("Zeus next to the cursor"). Returns a short status string.
    var onDebugPresence: ((String) -> String)?
    /// P0 item J ("quiet hours"): a WAV path, fed into the live dictation turn instead of the
    /// microphone. Returns "ok" or "ERROR ...".
    var onDebugDictateFile: ((String) async -> String)?
    /// Wake-word E2E: WAV into the Hey Zeus listener only (R24).
    var onDebugWakeFile: ((String) async -> String)?
    /// Scratch window: AX click and type, postToPid scroll, frontmost app and pointer stay put.
    var onDebugHandsLive: (() -> String)?
    /// Shows the before/after diff in the notch.
    var onDebugSelection: ((SelectionEdit) -> Void)?
    var onDebugUpdate: ((String) -> String)?
    var onDebugScreenShare: ((String) -> String)?
    var onDebugEngineLogos: ((String) async -> String)?
    /// PERM-CAM: camera and screen recording TCC state (no prompts).
    var onDebugPermissions: (() -> String)?
    /// Recordly silent capture check. Argument is the raw `record` flags; returns `ok=true ...` or an error line.
    var onDebugRecord: ((String) async -> String)?

    /// Shows a visible notch cue while a command-line request is capturing.
    /// Non-nil text shows the cue; nil clears it. It stays up until the capture has fully ended.
    var onSensitiveCue: ((String?) -> Void)?
    /// Offers removal of the plaintext key file after a verified Keychain import (explicit user confirmation).
    var onOfferKeyRemoval: ((String) -> Void)?

    init(voice: VoiceTurnController) {
        self.voice = voice
    }

    func handle(_ line: Data) async -> Data? {
        guard let command = try? JSONDecoder().decode(ZeusCommand.self, from: line) else {
            return try? JSONEncoder().encode(ZeusCommandReply(id: "unknown", ok: false, text: "Zeus couldn't read that command."))
        }
        return try? JSONEncoder().encode(await reply(to: command))
    }

    private func reply(to command: ZeusCommand) async -> ZeusCommandReply {
        let text = command.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let gateParts = text.split(separator: " ", maxSplits: 1).map(String.init)
        let gateSub = command.op == .debug ? (gateParts.first ?? "") : ""
        let gateArg = gateParts.count > 1 ? gateParts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if CLIAccess.isSensitive(op: command.op, debugSubcommand: gateSub, argument: gateArg) {
            guard CLIAccess.enabled else {
                return ZeusCommandReply(id: command.id, ok: false, text: CLIAccess.refusal)
            }
        }
        // Each capture command holds its own token; the cue clears only when the last one ends.
        let captureToken = UUID()
        if CLIAccess.enabled, CLIAccess.startsCapture(op: command.op, debugSubcommand: gateSub) {
            activeCaptures.insert(captureToken)
            onSensitiveCue?("A command-line request is capturing audio or screen")
        }
        defer {
            if activeCaptures.remove(captureToken) != nil, activeCaptures.isEmpty { onSensitiveCue?(nil) }
        }
        switch command.op {
        case .status:
            return ZeusCommandReply(id: command.id, ok: true, text: "Zeus is running.", status: await status())
        case .tasks:
            return ZeusCommandReply(id: command.id, ok: true,
                                    text: entries.isEmpty ? "No tasks yet." : "\(entries.count) recent task(s):",
                                    tasks: entries.map(\.info))
        case .cancel:
            let matches = entries.indices.filter {
                entries[$0].info.state == "running" && (text == "all" || entries[$0].info.id.hasPrefix(text))
            }
            guard !text.isEmpty, !matches.isEmpty else {
                return ZeusCommandReply(id: command.id, ok: false, text: "No running task matches \"\(text)\".")
            }
            for index in matches {
                if entries[index].info.op == ZeusCommand.Op.browse.rawValue { BrowserAgentRunner.shared.stop() }
                if entries[index].info.op == ZeusCommand.Op.research.rawValue { ResearchRunner.shared.stop() }
                entries[index].task?.cancel()
                voice.cancel(turn: entries[index].turn)
            }
            return ZeusCommandReply(id: command.id, ok: true, text: "Cancelled \(matches.count) task(s).")
        case .todo:
            return TodoController.shared.handleCLI(text, id: command.id)
        case .say:
            guard !text.isEmpty else { return ZeusCommandReply(id: command.id, ok: false, text: "Nothing to say.") }
            voice.say(text)
            return ZeusCommandReply(id: command.id, ok: true, text: "Speaking with the \(voice.voiceDescription).")
        case .ask:
            guard !text.isEmpty else { return ZeusCommandReply(id: command.id, ok: false, text: "Ask Zeus something.") }
            let deep = command.deep, speak = command.speak
            let restricted = !CLIAccess.enabled
            if restricted, let refusal = CLIAccess.restrictedAskRefusal(text) {
                return ZeusCommandReply(id: command.id, ok: false, text: refusal)
            }
            // Restricted turns run with capture and actions disabled (see CLIAccess.turnRestricted).
            return await CLIAccess.$turnRestricted.withValue(restricted) {
                await track(command, label: text) { voice, turn in
                    await voice.textTurn(text, turn: turn, deep: deep, speak: speak)
                }
            }
        case .browse:
            guard !text.isEmpty else { return ZeusCommandReply(id: command.id, ok: false, text: "Give the browser agent a goal.") }
            let speak = command.speak, separate = command.separate == true
            return await track(command, label: "browse: \(text)") { _, _ in
                guard let outcome = await BrowserAgentRunner.shared.start(goal: text, speak: speak, separate: separate) else {
                    return TurnResult(error: "The browser agent is already working on something. Stop it first (Esc).")
                }
                var result = TurnResult(spoken: outcome.spokenText, actions: ["browser agent: \(outcome.label)"])
                switch outcome {
                case .done, .askUser, .blocked: break
                case .stopped: result.cancelled = true
                default: result.error = outcome.spokenText
                }
                return result
            }
        case .code:
            guard !text.isEmpty else { return ZeusCommandReply(id: command.id, ok: false, text: "Give the coding agent a task.") }
            let tool = command.tool.flatMap(CodingTool.named), project = command.project
            let result = await CodeActions.shared.perform(.agent(tool: tool, project: project, dir: nil, task: text), speak: command.speak)
            return ZeusCommandReply(id: command.id, ok: result.ok, text: result.message,
                                    actions: result.ok ? ["terminal.agent"] : [], problems: result.ok ? [] : [result.message])
        case .term:
            let result = await CodeActions.shared.openTerminal(project: command.project, dir: nil)
            return ZeusCommandReply(id: command.id, ok: result.ok, text: result.message, actions: result.ok ? ["terminal.open"] : [])
        case .research:
            guard !text.isEmpty else { return ZeusCommandReply(id: command.id, ok: false, text: "Ask Zeus something to research.") }
            let depth: ResearchDepth = command.deep ? .deep : .quick, speak = command.speak
            let restricted = !CLIAccess.enabled
            return await track(command, label: "research: \(text)") { _, _ in
                guard let outcome = await ResearchRunner.shared.start(question: text, depth: depth, speak: speak, restricted: restricted) else {
                    return TurnResult(error: "Zeus is already researching something. Stop it first.")
                }
                var result = TurnResult(spoken: outcome.spoken)
                if let report = outcome.report { result.actions = ["report: \(report.path)"] }
                if outcome.cancelled { result.cancelled = true } else { result.error = outcome.problem }
                return result
            }
        case .listen:
            // Clamped again here: Int(inf) traps, and the socket does not have to come from the CLI parser.
            let requested = command.seconds ?? 6
            let seconds = requested.isFinite ? min(max(requested, 0.5), ZeusCLI.maxListenSeconds) : 6
            return await track(command, label: "voice turn, \(Int(seconds)) s") { voice, _ in
                await voice.listenTurn(seconds: seconds)
            }
        case .debug:
            let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
            let subcommand = parts.first ?? ""
            let rest = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            switch subcommand {
            case "open-settings":
                let section = rest.isEmpty ? nil : rest
                if let onDebugOpenSettings {
                    let ok = onDebugOpenSettings(section)
                    if !ok {
                        return ZeusCommandReply(id: command.id, ok: false,
                                                text: "Unknown settings page \"\(rest)\". Use a GSSection id (e.g. voice, general).")
                    }
                    return ZeusCommandReply(id: command.id, ok: true, text: "Settings opened\(section != nil ? " at \(section!)" : "").")
                } else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "Settings handler not wired.")
                }
            case "onboarding":
                let isPreview = rest.contains("--preview")
                if let onDebugOnboarding {
                    onDebugOnboarding(isPreview)
                    return ZeusCommandReply(id: command.id, ok: true, text: "Onboarding opened (preview: \(isPreview)).")
                } else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "Onboarding handler not wired.")
                }
            case "screenshot":
                let argument = rest.isEmpty ? nil : rest
                if let onDebugScreenshot {
                    let paths = await onDebugScreenshot(argument)
                    return ZeusCommandReply(id: command.id, ok: !paths.isEmpty,
                                            text: paths.isEmpty ? "Screenshot failed." : "Screenshot saved to \(paths.joined(separator: ", "))",
                                            actions: paths.map { "screenshot:\($0)" })
                } else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "Screenshot handler not wired.")
                }
            case "tab":
                guard !rest.isEmpty else {
                    // QA7 round 10: the old example list (day, control, reach, halo, sounds,
                    // theme) named no real `TopBarTab` case or title at all. These are real.
                    return ZeusCommandReply(id: command.id, ok: false, text: "tab needs a name (e.g. home, today, agents, music, dictation or murmure, polyglot)")
                }
                if let onDebugTab {
                    let ok = onDebugTab(rest)
                    return ZeusCommandReply(id: command.id, ok: ok, text: ok ? "Tab switched to \(rest)." : "Unknown tab \(rest).")
                } else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "Tab handler not wired.")
                }
            case "animate":
                guard !rest.isEmpty else {
                    // QA7 round 10: "halo" named no real effect (it's an Appearance arm-width
                    // setting, not an animation) and has been dropped; capslock/battery/a mascot
                    // state name (e.g. listening, speaking, agent) are real and now listed.
                    return ZeusCommandReply(id: command.id, ok: false, text: "animate needs an effect name (e.g. volume, brightness, thinking, glow, pulse, copy, edge, entrance, airdrop, capslock, battery, or a mascot state like listening)")
                }
                if let onDebugAnimate {
                    let ok = onDebugAnimate(rest)
                    return ZeusCommandReply(id: command.id, ok: ok, text: ok ? "Animation \(rest) triggered." : "Unknown animation \(rest).")
                } else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "Animation handler not wired.")
                }
            case "hud-state":
                if let onDebugHUDState {
                    return ZeusCommandReply(id: command.id, ok: true, text: onDebugHUDState())
                } else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "HUD state handler not wired.")
                }
            case "presence":
                let arg = rest.isEmpty ? "state" : rest
                if let onDebugPresence {
                    return ZeusCommandReply(id: command.id, ok: true, text: onDebugPresence(arg))
                } else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "Presence handler not wired.")
                }
            case "dictate-file":
                guard !rest.isEmpty else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "dictate-file needs a wav path")
                }
                if let onDebugDictateFile {
                    let result = await onDebugDictateFile(rest)
                    return ZeusCommandReply(id: command.id, ok: result == "ok", text: result)
                } else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "dictate-file handler not wired.")
                }
            case "wake-file":
                guard !rest.isEmpty else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "wake-file needs a wav path")
                }
                if let onDebugWakeFile {
                    let result = await onDebugWakeFile(rest)
                    return ZeusCommandReply(id: command.id, ok: result == "ok", text: result)
                } else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "wake-file handler not wired.")
                }
            case "brain-route":
                guard !rest.isEmpty else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "brain-route needs the words to classify")
                }
                return ZeusCommandReply(id: command.id, ok: true, text: InstantTable.describe(rest))
            case "second-brain-lookup":
                let parsed = Self.secondBrainLookupArgs(rest)
                guard !parsed.topic.isEmpty else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "Usage: second-brain-lookup [--vault path] <topic>")
                }
                guard let vault = parsed.vault, SecondBrain.looksLikeVault(vault) else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "No vault. Pass --vault or set ZEUS_BRAIN_FIXTURE.")
                }
                let report = BrainRecall.debugReport(vault: vault, topic: parsed.topic)
                return ZeusCommandReply(id: command.id, ok: report.hasPrefix("ok"), text: report)
            case "present":
                return ZeusCommandReply(id: command.id, ok: true, text: PresentProbe.report())
            case "present-timeline":
                let spoken = rest.isEmpty ? "Explain the Pythagorean theorem and draw it" : rest
                return ZeusCommandReply(id: command.id, ok: true, text: PresentTimeline.report(text: spoken))
            case "update":
                if let onDebugUpdate {
                    return ZeusCommandReply(id: command.id, ok: true, text: onDebugUpdate(rest))
                } else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "update handler not wired.")
                }
            case "screen-share":
                if let onDebugScreenShare {
                    return ZeusCommandReply(id: command.id, ok: true, text: onDebugScreenShare(rest))
                } else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "screen-share handler not wired.")
                }
            case "engine-logos":
                let path = rest.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "Usage: engine-logos <directory>")
                }
                if let onDebugEngineLogos {
                    let text = await onDebugEngineLogos(path)
                    if text.hasPrefix("ERROR") {
                        return ZeusCommandReply(id: command.id, ok: false, text: text)
                    }
                    let paths = text.split(separator: "\n").map(String.init)
                    return ZeusCommandReply(id: command.id, ok: !paths.isEmpty,
                                            text: paths.isEmpty ? "Engine logo export failed." : "Engine logo rows saved (\(paths.count) files).",
                                            actions: paths.map { "screenshot:\($0)" })
                } else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "engine-logos handler not wired.")
                }
            case "import-assistant-key":
                let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.first == "anthropic", parts.count == 2 else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "Usage: import-assistant-key anthropic <path>")
                }
                let outcome = AssistantKeyImporter.outcome(forFile: parts[1])
                if outcome.imported, let source = outcome.removableSource { onOfferKeyRemoval?(source) }
                return ZeusCommandReply(id: command.id, ok: outcome.imported, text: outcome.message)
            case "wake-false-triggers":
                let hits = WakeFalseTriggerFixtures.falseTriggers()
                if hits.isEmpty {
                    return ZeusCommandReply(id: command.id, ok: true, text: "ok 0/\(WakeFalseTriggerFixtures.podcastLines.count)")
                }
                return ZeusCommandReply(id: command.id, ok: false, text: "false triggers: \(hits.count) \(hits.prefix(3).joined(separator: " | "))")
            case "hands":
                let report = HandsAcceptance.report()
                HandsCommandLogger.append(raw: report.log)
                return ZeusCommandReply(id: command.id, ok: report.passed, text: report.text)
            case "hands-live":
                guard let onDebugHandsLive else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "Hands live handler not wired.")
                }
                let text = onDebugHandsLive()
                return ZeusCommandReply(id: command.id, ok: text.contains("\nPASS") || text.hasPrefix("PASS"), text: text)
            case "learn":
                if rest == "list" {
                    let phrases = LearnedShortcutDisk.shared.list().map(\.phrase)
                    return ZeusCommandReply(id: command.id, ok: true, text: phrases.isEmpty ? "empty" : phrases.joined(separator: "\n"))
                }
                if rest == "undo" {
                    let undone = LearnedShortcutDisk.shared.undo()
                    return ZeusCommandReply(id: command.id, ok: undone, text: undone ? "Undone." : "Nothing to undo.")
                }
                let report = LearnAcceptance.report()
                return ZeusCommandReply(id: command.id, ok: report.passed, text: report.text)
            case "selection":
                let report = SelectionAcceptance.report()
                if let edit = SelectionRewrite.plan(utterance: "make this shorter", selection: "hello there friend") {
                    onDebugSelection?(edit)
                }
                return ZeusCommandReply(id: command.id, ok: report.passed, text: report.text)
            case "clean-room":
                let noticesURL = Bundle.main.url(forResource: "NOTICES", withExtension: "txt")
                    ?? URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent().appendingPathComponent("Resources/NOTICES.txt")
                let notices = (try? String(contentsOf: noticesURL, encoding: .utf8)) ?? ""
                let report = AtticusCleanRoom.report(notices: notices, sourceRoot: nil)
                return ZeusCommandReply(id: command.id, ok: report.passed, text: report.text)
            case "on-device-speech":
                let report = OnDeviceSpeechAcceptance.report()
                return ZeusCommandReply(id: command.id, ok: report.passed, text: report.text)
            case "permissions":
                if let onDebugPermissions {
                    let text = onDebugPermissions()
                    return ZeusCommandReply(id: command.id, ok: text.hasPrefix("ok=true"), text: text)
                } else {
                    return ZeusCommandReply(id: command.id, ok: false, text: "permissions handler not wired.")
                }
            case "record":
                return await Self.recordReply(id: command.id, argument: rest, handler: onDebugRecord)
            default:
                return ZeusCommandReply(id: command.id, ok: false, text: DebugSubcommandCatalog.unknownMessage(subcommand))
            }
        }
    }

    /// The `record` debug reply, with the handler injected so tests never need a voice controller.
    /// Main-actor like its only caller: the handler is a main-actor closure, so it never crosses actors.
    static func recordReply(id: String, argument: String,
                            handler: ((String) async -> String)?) async -> ZeusCommandReply {
        guard let handler else {
            return ZeusCommandReply(id: id, ok: false, text: "record handler not wired.")
        }
        let result = await handler(argument)
        return ZeusCommandReply(id: id, ok: result.hasPrefix("ok=true"), text: result)
    }

    private func track(_ command: ZeusCommand, label: String,
                       work: @escaping @MainActor @Sendable (VoiceTurnController, UUID) async -> TurnResult) async -> ZeusCommandReply {
        let turn = UUID()
        let info = ZeusTaskInfo(id: command.id, op: command.op.rawValue, text: String(label.prefix(80)),
                                state: "running", started: Date())
        let voice = self.voice
        let task = Task { await work(voice, turn) }
        entries.append(Entry(info: info, turn: turn, task: task))
        if entries.count > 20 { entries.removeFirst(entries.count - 20) }

        let result = await task.value
        let state = result.cancelled ? "cancelled" : (result.error != nil ? "failed" : "done")
        if let index = entries.firstIndex(where: { $0.info.id == command.id }) {
            entries[index].info.state = state
            entries[index].task = nil
        }
        let text = result.error ?? (result.cancelled ? "Cancelled." : result.spoken)
        return ZeusCommandReply(id: command.id, ok: result.error == nil && !result.cancelled, text: text,
                                actions: result.actions, problems: result.problems)
    }

    private func status() async -> [String: String] {
        let health = await voice.brain.healthCheck()
        let running = entries.filter { $0.info.state == "running" }.count
        let brainLine: String = {
            if AnthropicAPIProvider.hasKey { return "anthropic API (Keychain), ready" }
            return "claude CLI, \(Self.describe(health))"
        }()
        return [
            "app": "running (pid \(ProcessInfo.processInfo.processIdentifier))",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            "socket": ZeusPaths.socket.path,
            "brain": brainLine,
            "voice": voice.voiceDescription,
            "talk key": Preferences.shared.talkKeyHint,
            "talk shortcut": Preferences.shared.pushToTalk.title,
            "dictation shortcut": DictationSettings.shared.key?.title ?? "off",
            "key access": KeyListenAccess.granted ? "ok (\(KeyListenAccess.accessibility ? "Accessibility" : "Input Monitoring"))" : "none: allow Accessibility or Input Monitoring",
            "wake word": WakeWordController.shared.cliStatus,
            "voice access": "mic \(VoicePermissions.mic), speech \(VoicePermissions.speech)",
            "listening": voice.isListening ? "yes" : "no",
            "speaking": voice.isSpeaking ? "yes" : "no",
            "approval": voice.hasPendingApproval ? "waiting for you in the notch" : "none",
            "tasks running": "\(running)",
        ]
    }

    static func describe(_ health: ProviderHealth) -> String {
        switch health {
        case .ready(let version): "ready" + (version.map { " (\($0))" } ?? "")
        case .notInstalled: "not installed"
        case .notLoggedIn(let hint): "not logged in: \(hint)"
        case .outdated(let found, let minimum): "outdated (\(found), needs \(minimum))"
        case .unreachable(let reason): "unreachable: \(reason)"
        }
    }

    private static func secondBrainLookupArgs(_ rest: String) -> (vault: URL?, topic: String) {
        var text = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        var vault: URL?
        if text.hasPrefix("--vault ") {
            let tail = String(text.dropFirst("--vault ".count))
            guard let space = tail.firstIndex(of: " ") else { return (nil, "") }
            let path = String(tail[..<space])
            text = String(tail[space...]).trimmingCharacters(in: .whitespacesAndNewlines)
            vault = URL(fileURLWithPath: path)
        }
        if vault == nil, let env = ProcessInfo.processInfo.environment["ZEUS_BRAIN_FIXTURE"], !env.isEmpty {
            vault = URL(fileURLWithPath: env)
        }
        if vault == nil, let root = BrainToday.defaultRoot() { vault = root }
        return (vault, text)
    }
}

/// Puts the bundled `zeus` CLI next to zeus-hook in ZEUS's bin folder.
/// Add it to your PATH with: ln -s "$HOME/Library/Application Support/Zeus/bin/zeus" /usr/local/bin/zeus
enum CLIInstaller {
    static func install() {
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/zeus")
        let files = FileManager.default
        guard files.isExecutableFile(atPath: source.path) else { return }
        let target = ZeusPaths.binDirectory.appendingPathComponent("zeus")
        try? files.createDirectory(at: ZeusPaths.binDirectory, withIntermediateDirectories: true)
        if files.contentsEqual(atPath: source.path, andPath: target.path) { return }
        try? files.removeItem(at: target)
        try? files.copyItem(at: source, to: target)
    }
}
