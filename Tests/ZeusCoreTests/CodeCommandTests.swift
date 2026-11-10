import Foundation
import Testing
@testable import ZeusCore

@Suite struct CodeCommandTests {
    private func action(_ json: String) -> ZeusAction? {
        guard case .action(let action)? = ZeusTagParser.parse("[ACTION:\(json)] Okay.").tags.first else { return nil }
        return action
    }

    private func command(_ json: String) -> CodeCommand? { action(json).flatMap(CodeCommand.init) }

    // MARK: Tags

    @Test func terminalAgentTag() {
        #expect(command(#"{"type":"terminal.agent","tool":"codex","project":"zeus","task":"fix the failing tests"}"#)
                == .agent(tool: .codex, project: "zeus", dir: nil, task: "fix the failing tests"))
        #expect(command(#"{"type":"terminal.agent","task":"add a README","dir":"~/dev/x"}"#)
                == .agent(tool: nil, project: nil, dir: "~/dev/x", task: "add a README"))
        #expect(command(#"{"type":"terminal.agent","tool":"cursor-agent","task":"x"}"#) == .agent(tool: .cursorAgent, project: nil, dir: nil, task: "x"))
        #expect(command(#"{"type":"terminal.agent","tool":"unknown","task":"x"}"#) == .agent(tool: nil, project: nil, dir: nil, task: "x"))
        #expect(command(#"{"type":"terminal.agent","project":"zeus"}"#) == nil) // no task
        #expect(command(#"{"type":"terminal.agent","task":"   "}"#) == nil)
    }

    @Test func terminalOpenAndRunTags() {
        #expect(command(#"{"type":"terminal.open"}"#) == .openTerminal(project: nil, dir: nil))
        #expect(command(#"{"type":"terminal.open","project":"polyglot"}"#) == .openTerminal(project: "polyglot", dir: nil))
        #expect(command(#"{"type":"terminal.open","dir":"/tmp"}"#) == .openTerminal(project: nil, dir: "/tmp"))
        #expect(command(#"{"type":"terminal.run","command":"git status","dir":"~/dev/zeus"}"#) == .run(command: "git status", dir: "~/dev/zeus"))
        #expect(command(#"{"type":"terminal.run","command":"ls"}"#) == .run(command: "ls", dir: nil))
        #expect(command(#"{"type":"terminal.run"}"#) == nil)
    }

    @Test func researchTag() {
        #expect(command(#"{"type":"research","question":"how do heat pumps work","depth":"deep"}"#) == .research(question: "how do heat pumps work", depth: .deep))
        #expect(command(#"{"type":"research","question":"x"}"#) == .research(question: "x", depth: .quick))
        #expect(command(#"{"type":"research","question":"x","depth":"bogus"}"#) == .research(question: "x", depth: .quick))
        #expect(command(#"{"type":"research","topic":"y"}"#) == .research(question: "y", depth: .quick))
        #expect(command(#"{"type":"research"}"#) == nil)
    }

    @Test func otherActionsAreNotCodeCommands() {
        #expect(command(#"{"type":"browser.back"}"#) == nil)
        #expect(command(#"{"type":"browser.agent","goal":"x"}"#) == nil)
    }

    @Test func tagsParseAtTheStartOfAReplyAndLeaveTheSpeech() {
        let result = ZeusTagParser.parse(#"[ACTION:{"type":"terminal.agent","project":"zeus","task":"fix it, it's \"broken\""}] Starting Claude in Zeus."#)
        #expect(result.spokenText == "Starting Claude in Zeus.")
        #expect(result.tags.count == 1)
        guard case .action(let action) = result.tags[0], let parsed = CodeCommand(action) else { Issue.record("not an action"); return }
        #expect(parsed == .agent(tool: nil, project: "zeus", dir: nil, task: "fix it, it's \"broken\""))
    }

    @Test func tagTextRoundTrips() {
        for kind in [ZeusAction.Kind.terminalAgent, .terminalOpen, .terminalRun, .research] {
            let original = ZeusAction(kind: kind, payload: ["task": .string("t \"q\""), "command": .string("ls"), "question": .string("q")])
            guard case .action(let back)? = ZeusTagParser.parse(original.tagText).tags.first else { Issue.record("\(kind) did not parse"); continue }
            #expect(back.kind == kind)
            #expect(back.payload["task"]?.stringValue == "t \"q\"")
        }
        #expect(ZeusAction.Kind.terminalAgent.rawValue == "terminal.agent")
        #expect(ZeusAction.Kind.research.rawValue == "research")
    }

    @Test func streamedTagsArriveWhole() {
        var parser = ZeusTagStreamParser()
        var outputs = parser.feed(#"[ACTION:{"type":"resea"#)
        #expect(outputs.isEmpty)
        outputs = parser.feed(#"rch","question":"x","depth":"quick"}] Looking into it."#)
        #expect(outputs.contains { if case .tag(.action(let a)) = $0 { a.kind == .research } else { false } })
        #expect(outputs.contains(.text("Looking into it.")))
    }

    @Test func pathExpansion() {
        #expect(CodeCommand.expandPath("~/dev/zeus", home: "/Users/t") == "/Users/t/dev/zeus")
        #expect(CodeCommand.expandPath("~", home: "/Users/t") == "/Users/t")
        #expect(CodeCommand.expandPath("/tmp/a/../b") == "/tmp/b")
        #expect(CodeCommand.expandPath("zeus") == nil)
        #expect(CodeCommand.expandPath("") == nil)
    }

    // MARK: CLI

    @Test func zeusCodeCommand() throws {
        let plain = try ZeusCLI.parse(["code", "fix the failing tests"])
        #expect(plain.command?.op == .code)
        #expect(plain.command?.text == "fix the failing tests")
        #expect(plain.command?.project == nil && plain.command?.tool == nil)

        let full = try ZeusCLI.parse(["code", "add", "dark", "mode", "--in", "polyglot", "--tool", "codex"])
        #expect(full.command?.text == "add dark mode")
        #expect(full.command?.project == "polyglot")
        #expect(full.command?.tool == "codex")
        #expect(try ZeusCLI.parse(["code", "x", "--tool", "cursor"]).command?.tool == "cursor-agent")

        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["code"]) }
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["code", "x", "--tool", "copilot"]) }
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["code", "x", "--in"]) }
    }

    @Test func zeusResearchCommand() throws {
        let quick = try ZeusCLI.parse(["research", "how do heat pumps work"])
        #expect(quick.command?.op == .research && quick.command?.deep == false)
        let deep = try ZeusCLI.parse(["research", "how do heat pumps work", "--deep"])
        #expect(deep.command?.deep == true)
        #expect(deep.timeout > quick.timeout)
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["research"]) }
    }

    @Test func zeusTermCommand() throws {
        let bare = try ZeusCLI.parse(["term"])
        #expect(bare.command?.op == .term && bare.command?.project == nil && bare.command?.text == nil)
        let project = try ZeusCLI.parse(["term", "zeus"])
        #expect(project.command?.project == "zeus")
        #expect(try ZeusCLI.parse(["term", "--in", "polyglot"]).command?.project == "polyglot")
        #expect(try ZeusCLI.parse(["term", "my", "project"]).command?.project == "my project")
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["term", "a", "--in", "b"]) }
    }

    @Test func theNewCommandsSurviveTheSocket() throws {
        let command = ZeusCommand(op: .code, text: "x", project: "zeus", tool: "codex")
        let back = try JSONDecoder().decode(ZeusCommand.self, from: JSONEncoder().encode(command))
        #expect(back == command)
        // an older CLI's line (no project/tool keys) still decodes
        let old = #"{"kind":"zeus.command","v":1,"id":"1","op":"ask","text":"hi","deep":false,"speak":true}"#
        let decoded = try JSONDecoder().decode(ZeusCommand.self, from: Data(old.utf8))
        #expect(decoded.project == nil && decoded.tool == nil && decoded.op == .ask)
    }

    @Test func usageMentionsTheNewCommands() {
        for word in ["zeus code", "zeus research", "zeus term"] { #expect(ZeusCLI.usage.contains(word)) }
    }
}
