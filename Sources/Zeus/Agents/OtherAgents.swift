import Foundation
import Observation
import SwiftUI
import ZeusCore

/// Connects Codex, Gemini CLI and cursor-agent to the notch by adding ZEUS's hook to each
/// tool's own config, with a timestamped backup first. Only ZEUS's entries are ever removed.
enum AgentHookInstaller {
    /// `ZEUS_AGENT_CONFIG_HOME` points the installer at a fake home, for tests and scripts.
    static var home: URL {
        if let override = ProcessInfo.processInfo.environment["ZEUS_AGENT_CONFIG_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func url(_ agent: AgentHookConfig.Agent) -> URL { home.appendingPathComponent(agent.relativePath) }

    /// Whether the agent's CLI looks present (its config folder exists).
    static func isAvailable(_ agent: AgentHookConfig.Agent) -> Bool {
        FileManager.default.fileExists(atPath: url(agent).deletingLastPathComponent().path)
    }

    /// The config file exists but is not strict JSON (a comment, a trailing comma): it is left alone.
    struct UnreadableConfig: LocalizedError {
        let path: String
        var errorDescription: String? { "couldn't read \(path). Fix it or move it aside, then try again." }
    }

    static func isInstalled(_ agent: AgentHookConfig.Agent) -> Bool {
        guard let config = try? read(agent) else { return false }
        return AgentHookConfig.isInstalled(in: config, agent: agent)
    }

    static func install(_ agent: AgentHookConfig.Agent) throws {
        // Read first: a file that doesn't parse stops here, before anything is written.
        let config = try read(agent)
        try ClaudeHookInstaller.refreshHelper()
        try backup(agent)
        try write(AgentHookConfig.install(into: config, agent: agent, helper: ClaudeHookInstaller.installedHook.path), to: agent)
    }

    static func uninstall(_ agent: AgentHookConfig.Agent) throws {
        guard let config = try read(agent) else { return }
        try backup(agent)
        try write(AgentHookConfig.uninstall(from: config, agent: agent), to: agent)
    }

    /// Nil when the file is missing or empty; throws when it exists but is not a JSON object.
    private static func read(_ agent: AgentHookConfig.Agent) throws -> JSONValue? {
        let target = url(agent)
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        let shown = "~/\(agent.relativePath)"
        guard let data = try? Data(contentsOf: target) else { throw UnreadableConfig(path: shown) }
        if data.allSatisfy({ [0x20, 0x09, 0x0A, 0x0D].contains($0) }) { return nil }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data), case .object = value else {
            throw UnreadableConfig(path: shown)
        }
        return value
    }

    private static func backup(_ agent: AgentHookConfig.Agent) throws {
        let source = url(agent)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        var target = source.deletingLastPathComponent().appendingPathComponent("\(source.lastPathComponent).zeus-backup-\(stamp)")
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = source.deletingLastPathComponent().appendingPathComponent("\(source.lastPathComponent).zeus-backup-\(stamp)-\(counter)")
            counter += 1
        }
        try FileManager.default.copyItem(at: source, to: target)
    }

    private static func write(_ config: JSONValue, to agent: AgentHookConfig.Agent) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let target = url(agent)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(config).write(to: target, options: .atomic)
    }
}

/// Settings rows to connect each agent.
@MainActor
@Observable
final class OtherAgentsState {
    static let shared = OtherAgentsState()
    var installed: [AgentHookConfig.Agent: Bool] = [:]
    var problem: String?

    func refresh() {
        for agent in AgentHookConfig.Agent.allCases { installed[agent] = AgentHookInstaller.isInstalled(agent) }
    }

    func set(_ agent: AgentHookConfig.Agent, on: Bool) {
        do {
            if on { try AgentHookInstaller.install(agent) } else { try AgentHookInstaller.uninstall(agent) }
            problem = nil
        } catch {
            problem = "\(agent.title): \(error.localizedDescription)"
        }
        refresh()
    }
}

struct OtherAgentsSection: View {
    let state = OtherAgentsState.shared

    var body: some View {
        Section("Other agents") {
            ForEach(AgentHookConfig.Agent.allCases, id: \.self) { agent in
                Toggle(isOn: Binding(get: { state.installed[agent] == true }, set: { state.set(agent, on: $0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show \(agent.title) in the notch")
                        Text(AgentHookInstaller.isAvailable(agent) ? "Adds ZEUS to ~/\(agent.relativePath), with a backup." : "\(agent.title) is not set up on this Mac.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .disabled(!AgentHookInstaller.isAvailable(agent) && state.installed[agent] != true)
            }
            if let problem = state.problem {
                Text(problem).font(.callout).foregroundStyle(.red)
            }
            Text("Codex sessions show up from their logs even without this; the hook adds approvals and is instant.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .onAppear { state.refresh() }
    }
}

/// Follows Codex from its rollout logs when its hooks are not connected: every 4 seconds it
/// reads only what recently touched files gained. Nothing runs while Codex is idle.
@MainActor
final class CodexSessionWatcher {
    private let ingest: (HookEvent) -> Void
    private var timer: Timer?
    private var files: [URL: (offset: Int, watch: CodexRolloutWatch)] = [:]
    /// Sessions shown in the notch and when their log last moved.
    private var shown: [URL: (session: String, last: Date)] = [:]
    /// A finished session leaves the notch after this long without new lines.
    static let idleTimeout: TimeInterval = 20 * 60
    private let root: URL

    init(ingest: @escaping (HookEvent) -> Void) {
        self.ingest = ingest
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        root = codexHome.appendingPathComponent("sessions", isDirectory: true)
    }

    func start() {
        guard timer == nil else { return }
        // Start at the end of today's files so old sessions don't replay.
        for url in recentFiles(within: 600) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            files[url] = (size, CodexRolloutWatch())
        }
        let timer = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        // Hooks are faster and richer; the watcher steps aside once they are connected.
        // With hooks on, the logs are read only for errors, which the Codex hook does not report.
        let hooksOn = AgentHookInstaller.isInstalled(.codex)
        for url in recentFiles(within: 120) {
            var state = files[url] ?? (0, CodexRolloutWatch())
            var offset = state.offset
            guard let (data, start) = UsageScanner.read(url, from: &offset) else { continue }
            if start == 0 { state.watch = CodexRolloutWatch() }
            let consumed = JSONLines.forEach(data, markers: ["\"session_meta\"", "\"user_message\"", "\"UserMessage\"",
                                                            "\"task_complete\"", "\"task_started\"", "\"turn_context\"",
                                                            "\"function_call\"", "\"custom_tool_call\"", "\"error\""], prefixLimit: 320) { line in
                if let change = state.watch.apply(line: line) {
                    if hooksOn { if case .failed = change { emit(change, watch: state.watch, file: url) } } else { emit(change, watch: state.watch, file: url) }
                }
            }
            state.offset = start + consumed
            files[url] = state
        }
        guard !hooksOn else { return }
        for (url, entry) in shown where Date().timeIntervalSince(entry.last) > Self.idleTimeout && files[url]?.watch.working != true {
            ingest(HookEvent(source: .codex, event: "SessionEnd", session: entry.session, needsDecision: false))
            shown[url] = nil
            files[url] = nil
        }
    }

    private func emit(_ change: CodexRolloutWatch.Change, watch: CodexRolloutWatch, file: URL) {
        let session = watch.session ?? file.deletingPathExtension().lastPathComponent
        shown[file] = (session, Date())
        let event: (String, String?, String?) = switch change {
        case .started: ("SessionStart", nil, nil)
        case .prompt(let text): ("UserPromptSubmit", text, nil)
        case .tool(let name): ("PreToolUse", nil, ["shell", "exec", "exec_command", "local_shell"].contains(name) ? "Bash" : name)
        case .finished(let message): ("Stop", message, nil)
        case .failed(let reason): ("StopFailure", reason, nil)
        }
        ingest(HookEvent(source: .codex, event: event.0, session: session, cwd: watch.cwd, tool: event.2,
                         detail: event.1.map { String($0.prefix(400)) }, needsDecision: false))
    }

    private func recentFiles(within seconds: TimeInterval) -> [URL] {
        let cutoff = Date().addingTimeInterval(-seconds)
        let calendar = Calendar.current
        // Rollouts live in YYYY/MM/DD folders; only today's and yesterday's are looked at.
        let days = [Date(), Date().addingTimeInterval(-86_400)].map { date -> URL in
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return root.appendingPathComponent(String(format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0))
        }
        return days.flatMap { folder -> [URL] in
            let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            return items.filter { url in
                url.pathExtension == "jsonl"
                    && ((try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >= cutoff
            }
        }
    }
}
