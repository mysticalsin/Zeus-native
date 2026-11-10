import Foundation
import Testing
@testable import ZeusCore

@Suite("Agent hooks")
struct AgentHooksTests {
    func json(_ text: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

    @Test func codexKeepsClaudeShapedEvents() {
        let event = AgentHookNormalizer.normalize(json(#"{"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/r","tool_name":"Bash","tool_input":{"command":"ls"}}"#), source: .codex)
        #expect(event?.event == "PermissionRequest" && event?.needsDecision == true)
        #expect(event?.tool == "Bash" && event?.input?["command"]?.stringValue == "ls")
        #expect(AgentHookNormalizer.normalize(json("{}"), source: .codex) == nil)
    }

    @Test func geminiMapsToCommonEvents() {
        let prompt = AgentHookNormalizer.normalize(json(#"{"hook_event_name":"BeforeAgent","session_id":"g","cwd":"/site","prompt":"fix the build"}"#), source: .gemini)
        #expect(prompt?.event == "UserPromptSubmit" && prompt?.detail == "fix the build" && prompt?.cwd == "/site")
        let tool = AgentHookNormalizer.normalize(json(#"{"hook_event_name":"BeforeTool","session_id":"g","tool_name":"run_shell_command","tool_input":{"command":"npm test"}}"#), source: .gemini)
        #expect(tool?.event == "PreToolUse" && tool?.tool == "Bash" && tool?.needsDecision == false)
        let done = AgentHookNormalizer.normalize(json(#"{"hook_event_name":"AfterAgent","session_id":"g","prompt_response":"Build fixed."}"#), source: .gemini)
        #expect(done?.event == "Stop" && done?.detail == "Build fixed.")
        #expect(AgentHookNormalizer.normalize(json(#"{"hook_event_name":"PreCompress"}"#), source: .gemini) == nil)
    }

    @Test func cursorMapsToCommonEvents() {
        let shell = AgentHookNormalizer.normalize(json(#"{"hook_event_name":"beforeShellExecution","conversation_id":"c","workspace_roots":["/api"],"command":"make"}"#), source: .cursor)
        #expect(shell?.event == "PreToolUse" && shell?.tool == "Bash" && shell?.input?["command"]?.stringValue == "make")
        #expect(shell?.session == "c" && shell?.cwd == "/api" && shell?.needsDecision == false)
        let edit = AgentHookNormalizer.normalize(json(#"{"hook_event_name":"afterFileEdit","conversation_id":"c","file_path":"/api/a.ts"}"#), source: .cursor)
        #expect(edit?.tool == "Edit" && edit?.input?["file_path"]?.stringValue == "/api/a.ts")
        let answer = AgentHookNormalizer.normalize(json(#"{"hook_event_name":"afterAgentResponse","conversation_id":"c","text":"Done, tests pass."}"#), source: .cursor)
        #expect(answer?.event == "AgentResponse" && answer?.detail == "Done, tests pass.")
        #expect(AgentHookNormalizer.normalize(json(#"{"hook_event_name":"stop","conversation_id":"c","status":"completed"}"#), source: .cursor)?.event == "Stop")
        #expect(AgentHookNormalizer.normalize(json(#"{"hook_event_name":"beforeReadFile"}"#), source: .cursor) == nil)
    }

    @Test func installKeepsOtherToolsAndIsIdempotent() throws {
        let existing = json(#"{"model":"x","hooks":{"AfterAgent":[{"hooks":[{"type":"command","command":"/other/bridge --source gemini"}]}]}}"#)
        let once = AgentHookConfig.install(into: existing, agent: .gemini, helper: "/Z/bin/zeus-hook")
        let twice = AgentHookConfig.install(into: once, agent: .gemini, helper: "/Z/bin/zeus-hook")
        #expect(once == twice)
        #expect(once["model"]?.stringValue == "x")
        let after = try #require(once["hooks"]?["AfterAgent"]?.arrayValue)
        #expect(after.count == 2)
        #expect(after[0]["hooks"]?.arrayValue?.first?["command"]?.stringValue == "/other/bridge --source gemini")
        #expect(after[1]["hooks"]?.arrayValue?.first?["command"]?.stringValue == AgentHookConfig.command(helper: "/Z/bin/zeus-hook", agent: .gemini))
        #expect(AgentHookConfig.isInstalled(in: once, agent: .gemini))
        #expect(!AgentHookConfig.isInstalled(in: existing, agent: .gemini))

        let removed = AgentHookConfig.uninstall(from: once, agent: .gemini)
        #expect(removed["hooks"]?["AfterAgent"]?.arrayValue?.count == 1)
        #expect(removed["hooks"]?["BeforeAgent"] == nil)
        #expect(!AgentHookConfig.isInstalled(in: removed, agent: .gemini))
    }

    @Test func commandIsGuarded() {
        #expect(AgentHookConfig.command(helper: "/Z/zeus-hook", agent: .codex) == #"/bin/sh -c '[ -x "/Z/zeus-hook" ] && "/Z/zeus-hook" --source codex || true'"#)
    }

    @Test func cursorAndCodexShapes() {
        let cursor = AgentHookConfig.install(into: nil, agent: .cursor, helper: "/Z/zeus-hook")
        #expect(cursor["version"] == .number(1))
        #expect(cursor["hooks"]?["stop"]?.arrayValue?.first?["command"]?.stringValue == AgentHookConfig.command(helper: "/Z/zeus-hook", agent: .cursor))
        let codex = AgentHookConfig.install(into: json(#"{"hooks":{}}"#), agent: .codex, helper: "/Z/zeus-hook")
        let permission = codex["hooks"]?["PermissionRequest"]?.arrayValue?.first?["hooks"]?.arrayValue?.first
        #expect(permission?["timeout"] == .number(120))
        #expect(AgentHookConfig.isInstalled(in: codex, agent: .codex))
        // A config with only our hooks comes back empty.
        #expect(AgentHookConfig.uninstall(from: cursor, agent: .cursor)["hooks"] == .object([:]))
    }

    @Test func codexRolloutWatch() {
        var watch = CodexRolloutWatch()
        func feed(_ text: String) -> CodexRolloutWatch.Change? { watch.apply(line: Data(text.utf8)) }
        #expect(feed(#"{"type":"session_meta","payload":{"session_id":"x1","cwd":"/repo"}}"#) == .started(cwd: "/repo"))
        #expect(watch.session == "x1")
        #expect(feed(#"{"type":"response_item","payload":{"type":"function_call","name":"shell"}}"#) == nil)
        #expect(feed(#"{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"UserMessage","content":[{"type":"text","text":"add tests"}]}}}"#) == .prompt("add tests"))
        #expect(watch.working)
        #expect(feed(#"{"type":"response_item","payload":{"type":"function_call","name":"apply_patch"}}"#) == .tool("apply_patch"))
        #expect(feed(#"{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"Added 3 tests."}}"#) == .finished("Added 3 tests."))
        #expect(!watch.working)
        #expect(feed("garbage") == nil)
    }
}
