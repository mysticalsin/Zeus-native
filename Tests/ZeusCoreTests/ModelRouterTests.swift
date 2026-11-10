import Foundation
import Testing
@testable import ZeusCore

@Suite("Model router")
struct ModelRouterTests {
    let all = Set(RouterEngine.allCases)

    @Test func detectionOnlyChecksFiles() {
        var checked: [String] = []
        let found = RouterEngine.installed(searchDirectories: ["/a", "/b"], extraPaths: [.codex: ["/Apps/codex"]]) { path in
            checked.append(path)
            return ["/b/claude", "/Apps/codex", "/a/cursor-agent"].contains(path)
        }
        #expect(found == [.claude: "/b/claude", .codex: "/Apps/codex", .cursorAgent: "/a/cursor-agent"])
        #expect(checked.contains("/a/grok") && checked.contains("/b/ollama"))
    }

    @Test func classifiesTasks() {
        #expect(RouterTask.classify("Fix this bug in my Swift function") == .code)
        #expect(RouterTask.classify("```\nlet x = 1\n```") == .code)
        #expect(RouterTask.classify("Research the latest notch apps and compare them") == .research)
        #expect(RouterTask.classify("Draft a blog post about ZEUS") == .longWriting)
        #expect(RouterTask.classify("Summarize my therapy notes privately") == .privateLocal)
        #expect(RouterTask.classify("What's 18% of 240?") == .quickAnswer)
        #expect(RouterTask.classify(Array(repeating: "word", count: 70).joined(separator: " ")) == .longWriting)
    }

    @Test func autoPicksBestInstalled() {
        let code = ModelRouter.route(task: .code, installed: all)
        #expect(code.engine == .claude)
        #expect(code.reason == "Code → Claude: best installed for code")
        #expect(ModelRouter.route(task: .research, installed: all).engine == .gemini)
        #expect(ModelRouter.route(task: .research, installed: [.claude, .codex]).engine == .claude)
    }

    @Test func skipsEnginesNearTheirLimit() {
        let decision = ModelRouter.route(task: .code, installed: all, usage: [.claude: 0.93, .codex: 0.4])
        #expect(decision.engine == .codex)
        #expect(decision.skipped[.claude] == "at 93% of its limit")
        #expect(decision.reason.contains("Claude at 93% of its limit"))
        // Everything full: the least-used one still answers.
        let full = ModelRouter.route(task: .code, installed: [.claude, .codex], usage: [.claude: 0.99, .codex: 0.95])
        #expect(full.engine == .codex)
        #expect(full.reason.hasSuffix("every engine is near its limit"))
    }

    @Test func overridesAndTheirFallbacks() {
        #expect(ModelRouter.route(task: .code, installed: all, choice: .engine(.grok)).engine == .grok)
        // Not installed: falls back to auto.
        #expect(ModelRouter.route(task: .code, installed: [.claude], choice: .engine(.grok)).engine == .claude)
        // Near its limit: falls back too.
        #expect(ModelRouter.route(task: .quickAnswer, installed: all, usage: [.claude: 0.95], choice: .engine(.claude)).engine == .gemini)
        #expect(RouterChoice(storageValue: "codex") == .engine(.codex))
        #expect(RouterChoice(storageValue: "nonsense") == .auto)
        #expect(RouterChoice.engine(.cursorAgent).storageValue == "cursorAgent")
    }

    @Test func privateTasksNeverLeaveTheMac() {
        #expect(ModelRouter.route(task: .privateLocal, installed: all).engine == .ollama)
        let none = ModelRouter.route(task: .privateLocal, installed: [.claude, .gemini])
        #expect(none.engine == nil)
        #expect(none.reason.contains("Ollama"))
        // Even a cloud override is refused for private work.
        #expect(ModelRouter.route(task: .privateLocal, installed: all, choice: .engine(.claude)).engine == .ollama)
        #expect(ModelRouter.route(task: .code, installed: []).engine == nil)
    }

    @Test func usageComesFromTheUsageTab() {
        let now = Date()
        let providers = [
            ProviderUsage(provider: .claude, meters: [.init(label: "5h", fraction: 0.92, tokens: 1, resetsAt: nil, estimated: true)],
                          todayTokens: 0, weekTokens: 0, weekCost: 0, daily: [], topModel: nil, lastActivity: now, plan: nil),
            ProviderUsage(provider: .codex, meters: [.init(label: "Weekly", fraction: nil, tokens: nil, resetsAt: nil, estimated: false)],
                          todayTokens: 0, weekTokens: 0, weekCost: 0, daily: [], topModel: nil, lastActivity: now, plan: nil),
        ]
        #expect(ModelRouter.usage(from: providers) == [.claude: 0.92])
    }

    @Test func chatMessagesKeepTheirEngine() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(ChatMessage.self, from: Data(#"{"id":"A1B2C3D4-0000-0000-0000-000000000001","role":"assistant","text":"hi","date":"2026-10-31T10:00:00Z","failed":false}"#.utf8))
        #expect(old.engine == nil && old.engineReason == nil)
        let new = ChatMessage(role: .assistant, text: "x", engine: RouterEngine.codex.rawValue, engineReason: "Code → Codex")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let back = try decoder.decode(ChatMessage.self, from: encoder.encode(new))
        #expect(back.engine == "codex" && back.engineReason == "Code → Codex")
    }

    @Test func voiceOrderPutsCursorLast() throws {
        #expect(ModelRouter.voiceOrder.first == .codex)
        #expect(ModelRouter.voiceOrder.last == .cursorAgent)
        let grok = try #require(ModelRouter.voiceOrder.firstIndex(of: .grok))
        let cursor = try #require(ModelRouter.voiceOrder.firstIndex(of: .cursorAgent))
        #expect(grok < cursor)
        #expect(ModelRouter.voiceOrder == [.codex, .gemini, .claude, .ollama, .grok, .cursorAgent])
    }

    @Test func headlessArguments() {
        let defaults = UserDefaults(suiteName: "zeus.router.\(UUID().uuidString)")!
        // Capped effort (ModelCap): never the account default, which can be "max".
        #expect(RouterEngine.codex.headlessArguments(prompt: "hi", defaults: defaults)
                == ["exec", "--skip-git-repo-check", "-c", "model_reasoning_effort=\"low\"", "hi"])
        #expect(RouterEngine.ollama.headlessArguments(prompt: "hi", localModel: "qwen", defaults: defaults) == ["run", "qwen", "hi"])
        #expect(RouterEngine.cursorAgent.binary == "cursor-agent")
    }
}
