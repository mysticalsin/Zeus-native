import Foundation
import ZeusCore

// zeus-hook: called by the hooks of Claude Code, Codex, Gemini CLI and cursor-agent.
// Usage: zeus-hook --source claude-code
//
// Reads the hook JSON on stdin and forwards it to the ZEUS app over its Unix socket.
// For PermissionRequest it waits for your decision in the notch and prints it. If ZEUS is not
// running, does not answer in time, or you let it pass, it prints nothing, and Claude Code shows
// its normal permission prompt. It never allows anything on its own.

// ZEUS's own `claude -p` brain calls must not show up as agent sessions.
if ProcessInfo.processInfo.environment["ZEUS_INTERNAL"] == "1" { exit(0) }

let arguments = CommandLine.arguments
let sourceArgument = arguments.firstIndex(of: "--source").flatMap { index in
    index + 1 < arguments.count ? arguments[index + 1] : nil
}
let source = sourceArgument.flatMap(HookEvent.Source.init(rawValue:)) ?? .claudeCode

let stdinData = FileHandle.standardInput.readDataToEndOfFile()
guard let payload = try? JSONDecoder().decode(JSONValue.self, from: stdinData) else { exit(0) }

// Every agent's payload becomes the same event names (Claude Code's); unknown events are dropped.
guard let normalized = AgentHookNormalizer.normalize(payload, source: source) else { exit(0) }
let needsDecision = normalized.needsDecision
// The terminal app from the environment, and the exact tty from the agent process above us.
var terminal = TerminalInfo.from(environment: ProcessInfo.processInfo.environment)
if let tty = ControllingTTY.find() {
    terminal = terminal ?? TerminalInfo()
    terminal?.tty = tty
}

let event = HookEvent(
    source: source,
    event: normalized.event,
    session: normalized.session,
    cwd: normalized.cwd,
    tool: normalized.tool,
    input: normalized.input,
    risk: normalized.tool == nil ? nil : CommandRisk.assess(tool: normalized.tool, input: normalized.input),
    detail: normalized.detail.map { String($0.prefix(400)) },
    needsDecision: needsDecision,
    terminal: terminal
)

guard let line = try? JSONEncoder().encode(event) else { exit(0) }
let reply = UnixSocket.request(
    path: ZeusPaths.socket.path,
    payload: line,
    expectReply: needsDecision,
    timeout: needsDecision ? 115 : 1
)

if needsDecision,
   let reply,
   let decision = try? JSONDecoder().decode(HookDecision.self, from: reply),
   let output = decision.claudePermissionRequestOutput(),
   let data = try? JSONEncoder().encode(JSONValue.object(output)) {
    FileHandle.standardOutput.write(data)
}
exit(0)
