import Foundation
import Testing
@testable import ZeusCore

@Suite("Agent cards")
struct AgentCardsTests {
    func json(_ text: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

    @Test func questionsParseFromAskUserQuestion() {
        let input = json(#"{"questions":[{"question":"Which database?","header":"DB","multiSelect":false,"options":[{"label":"Postgres","description":"Relational"},{"label":"SQLite"}]},{"question":"Extras?","multiSelect":true,"options":[{"label":"Auth"},{"label":"Logs"}]},{"header":"no question"}]}"#)
        let questions = AgentQuestion.parse(input)
        #expect(questions.count == 2)
        #expect(questions[0].header == "DB")
        #expect(questions[0].options.map(\.label) == ["Postgres", "SQLite"])
        #expect(questions[0].options[0].detail == "Relational")
        #expect(!questions[0].multiSelect && questions[1].multiSelect)
        #expect(AgentQuestion.parse(json(#"{"command":"ls"}"#)).isEmpty)
    }

    @Test func answersAreAddedToTheInput() {
        let input = json(#"{"questions":[{"question":"Which database?","options":[]}]}"#)
        let answered = AgentQuestion.answeredInput(input, answers: ["Which database?": ["Postgres"], "Extras?": ["Auth", "Logs"], "Skipped": []])
        #expect(answered["questions"]?.arrayValue?.count == 1)
        #expect(answered["answers"]?["Which database?"]?.stringValue == "Postgres")
        #expect(answered["answers"]?["Extras?"]?.stringValue == "Auth, Logs")
        #expect(answered["answers"]?["Skipped"] == nil)
    }

    @Test func allowCarriesUpdatedInputForClaude() throws {
        let decision = HookDecision(id: "1", decision: .allow, updatedInput: json(#"{"answers":{"Q":"A"}}"#))
        let output = try #require(decision.claudePermissionRequestOutput())
        let inner = output["hookSpecificOutput"]?["decision"]
        #expect(inner?["behavior"]?.stringValue == "allow")
        #expect(inner?["updatedInput"]?["answers"]?["Q"]?.stringValue == "A")
        // Older apps' replies without the field still decode.
        let old = try JSONDecoder().decode(HookDecision.self, from: Data(#"{"id":"1","decision":"deny","reason":"no"}"#.utf8))
        #expect(old.updatedInput == nil)
    }

    @Test func plans() {
        #expect(AgentPlan.text(json(#"{"plan":"  ## Plan\n1. Do it  "}"#)) == "## Plan\n1. Do it")
        #expect(AgentPlan.text(json(#"{"plan":"  "}"#)) == nil)
        #expect(AgentPlan.feedbackMessage("use SQLite").hasSuffix("feedback: use SQLite"))
        #expect(AgentPlan.feedbackMessage(" ").contains("Keep planning"))
    }

    @Test func editDiffShowsChangesWithContext() throws {
        let input = json(#"{"file_path":"/repo/App.swift","old_string":"a\nb\nc\nd\ne","new_string":"a\nb\nC\nd\ne"}"#)
        let diff = try #require(FileDiff.from(tool: "Edit", input: input))
        #expect(diff.fileName == "App.swift")
        #expect(diff.added == 1 && diff.removed == 1)
        #expect(diff.lines.map(\.kind) == [.context, .removed, .added, .context])
        #expect(diff.lines.map(\.text) == ["b", "c", "C", "d"])
        #expect(!diff.isNewFile)
    }

    @Test func writeAndMultiEditAndTruncation() throws {
        let write = try #require(FileDiff.from(tool: "Write", input: json(#"{"file_path":"/x/new.md","content":"1\n2\n3"}"#), maxLines: 2))
        #expect(write.isNewFile && write.added == 3 && write.removed == 0)
        #expect(write.lines.count == 2 && write.hiddenLines == 1)
        let multi = try #require(FileDiff.from(tool: "MultiEdit", input: json(#"{"file_path":"/x/a","edits":[{"old_string":"x","new_string":"y"},{"old_string":"p","new_string":""}]}"#)))
        #expect(multi.added == 1 && multi.removed == 2)
        #expect(FileDiff.from(tool: "Bash", input: json(#"{"command":"ls","file_path":"/x"}"#)) == nil)
        #expect(FileDiff.from(tool: "Edit", input: json(#"{"old_string":"a"}"#)) == nil)
    }

    @Test func terminalTargetFromEnvironment() {
        #expect(TerminalInfo.from(environment: [:]) == nil)
        let iterm = TerminalInfo.from(environment: ["TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "w0t0p0:ABC"])
        #expect(iterm?.targetBundleID == "com.googlecode.iterm2")
        #expect(iterm?.sessionID == "w0t0p0:ABC")
        let code = TerminalInfo.from(environment: ["TERM_PROGRAM": "vscode", "__CFBundleIdentifier": "com.todesktop.230313mzl4w4u92"])
        #expect(code?.targetBundleID == "com.todesktop.230313mzl4w4u92")
        #expect(TerminalInfo(program: "mystery").targetBundleID == nil)
        // Older events without the field still decode.
        let old = try? JSONDecoder().decode(HookEvent.self, from: Data(#"{"v":1,"id":"1","source":"claude-code","event":"Stop","needsDecision":false}"#.utf8))
        #expect(old?.terminal == nil && old?.event == "Stop")
    }

    @Test func completionSummary() {
        let start = Date(timeIntervalSince1970: 1000)
        let done = AgentCompletion(sessionID: "s", agent: "Claude Code", project: "zeus", summary: "All tests pass.\nCommitted.", startedAt: start, now: start.addingTimeInterval(245))
        #expect(done.summary == "All tests pass. Committed.")
        #expect(done.duration == 245)
        #expect(AgentCompletion(sessionID: "s", agent: "a", project: "p", summary: nil, startedAt: nil).summary == "Finished.")
        #expect(AgentCompletion.durationText(38) == "38 s")
        #expect(AgentCompletion.durationText(245) == "4 min")
        #expect(AgentCompletion.durationText(3900) == "1 h 05 min")
    }

    @Test func completionSummaryIsOneTrimmedLine() {
        let long = String(repeating: "word ", count: 80)
        let done = AgentCompletion(sessionID: "s", agent: "a", project: "p", summary: long, startedAt: nil)
        #expect(done.summary.count == 160)
        #expect(done.summary.hasSuffix("…"))
        #expect(!done.summary.contains("\n"))
        #expect(done.duration == nil)
        #expect(AgentCompletion(sessionID: "s", agent: "a", project: "p", summary: "  \n \n ", startedAt: nil).summary == "Finished.")
        #expect(AgentCompletion(sessionID: "s", agent: "a", project: "p", summary: "  Fixed it.  ", startedAt: nil).summary == "Fixed it.")
    }

    @Test func durationTextRoundsAcrossUnitBoundaries() {
        #expect(AgentCompletion.durationText(0) == "0 s")
        #expect(AgentCompletion.durationText(59.6) == "1 min")
        #expect(AgentCompletion.durationText(3599.6) == "1 h 00 min")
        #expect(AgentCompletion.durationText(7325) == "2 h 02 min")
    }

    @Test func questionsStayVisibleButSilentInFullScreen() {
        let held = AgentQuietPolicy.outcome(for: .question, fullScreen: true, quietEnabled: true, soundsEnabled: true)
        #expect(held == .init(present: true, sound: false))
        let normal = AgentQuietPolicy.outcome(for: .question, fullScreen: false, quietEnabled: true, soundsEnabled: true)
        #expect(normal == .init(present: true, sound: true))
        let muted = AgentQuietPolicy.outcome(for: .completion, fullScreen: false, quietEnabled: true, soundsEnabled: false)
        #expect(muted == .init(present: true, sound: false))
    }

    @Test func quietInFullScreen() {
        let loud = AgentQuietPolicy.outcome(for: .completion, fullScreen: false, quietEnabled: true, soundsEnabled: true)
        #expect(loud == .init(present: true, sound: true))
        #expect(AgentQuietPolicy.outcome(for: .peek, fullScreen: false, quietEnabled: true, soundsEnabled: true).sound == false)
        #expect(AgentQuietPolicy.outcome(for: .completion, fullScreen: true, quietEnabled: true, soundsEnabled: true) == .init(present: false, sound: false))
        #expect(AgentQuietPolicy.outcome(for: .approval, fullScreen: true, quietEnabled: true, soundsEnabled: true) == .init(present: true, sound: false))
        #expect(AgentQuietPolicy.outcome(for: .completion, fullScreen: true, quietEnabled: false, soundsEnabled: false) == .init(present: true, sound: false))
    }
}
