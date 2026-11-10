import Foundation
import Testing
@testable import ZeusCore

@Suite("Agent follow-ups")
struct AgentFollowUpsTests {
    @Test func terminalScriptSelectsByTTY() throws {
        let script = try #require(TerminalTabScript.script(for: TerminalInfo(bundleID: "com.apple.Terminal", tty: "/dev/ttys004")))
        #expect(script.contains(#"tty of t is "/dev/ttys004""#))
        #expect(script.contains("set selected of t to true"))
        #expect(TerminalTabScript.script(for: TerminalInfo(bundleID: "com.apple.Terminal")) == nil)
    }

    @Test func itermScriptUsesSessionIDAndTTY() throws {
        let info = TerminalInfo(program: "iTerm.app", sessionID: "w0t2p0:6B2C1A8E-1F0D-4C55-9F7E-0D1B2C3D4E5F", tty: "/dev/ttys009")
        let script = try #require(TerminalTabScript.script(for: info))
        #expect(script.contains(#"unique id of s is "6B2C1A8E-1F0D-4C55-9F7E-0D1B2C3D4E5F""#))
        #expect(script.contains(#"tty of s is "/dev/ttys009""#))
        #expect(TerminalTabScript.script(for: TerminalInfo(program: "ghostty", tty: "/dev/ttys1")) == nil)
    }

    @Test func unsafeValuesNeverReachTheScript() {
        #expect(TerminalTabScript.script(for: TerminalInfo(bundleID: "com.apple.Terminal", tty: "/dev/ttys1\" & do shell script \"x")) == nil)
        #expect(TerminalTabScript.safe("/dev/ttys001") == "/dev/ttys001")
        #expect(TerminalTabScript.safe("") == nil)
    }

    @Test func controllingTTYLookupIsSafe() {
        // Under `swift test` there may be no terminal; the lookup must simply return nil or a device path.
        let tty = ControllingTTY.find(startingAt: getpid())
        #expect(tty == nil || tty!.hasPrefix("/dev/"))
        #expect(ControllingTTY.find(startingAt: 0) == nil)
    }

    @Test func answerPathsBuildTheRightDecision() {
        let answers = ["Which DB?": ["SQLite"], "Extras?": ["Auth", "Logs"]]
        let allow = QuestionAnswerPath.allowWithAnswers.decision(id: "1", input: .object(["questions": .array([])]), answers: answers)
        #expect(allow.decision == .allow)
        #expect(allow.updatedInput?["answers"]?["Which DB?"]?.stringValue == "SQLite")
        let deny = QuestionAnswerPath.denyWithAnswer.decision(id: "1", input: nil, answers: answers)
        #expect(deny.decision == .deny && deny.updatedInput == nil)
        #expect(deny.reason == "The user already answered these questions in ZEUS:\n- Extras? → Auth, Logs\n- Which DB? → SQLite\nContinue with these answers and do not ask them again.")
        // Claude Code reads the refusal as the PermissionRequest message.
        let output = deny.claudePermissionRequestOutput()
        #expect(output?["hookSpecificOutput"]?["decision"]?["message"]?.stringValue == deny.reason)
    }

    @Test func trackerKeepsAllowWhenHonoured() {
        var tracker = QuestionAnswerTracker()
        tracker.sent(session: "s", answers: ["Q": ["SQLite"]])
        let honoured = tracker.toolResult(session: "s", text: #"{"answers":{"Q":"SQLite"}}"#)
        #expect(honoured == true)
        #expect(tracker.path == .allowWithAnswers && tracker.pending == nil)
        #expect(tracker.toolResult(session: "s", text: "anything") == nil)
    }

    @Test func trackerFallsBackWhenResultLacksAnswer() {
        var tracker = QuestionAnswerTracker()
        tracker.sent(session: "s", answers: ["Q": ["SQLite"]])
        #expect(tracker.toolResult(session: "other", text: "") == nil)
        let honoured = tracker.toolResult(session: "s", text: "User has not answered yet")
        #expect(honoured == false)
        #expect(tracker.path == .denyWithAnswer)
        // Once on the deny path nothing is tracked.
        tracker.sent(session: "s", answers: ["Q": ["A"]])
        #expect(tracker.pending == nil)
        tracker.reset()
        #expect(tracker.path == .allowWithAnswers)
    }

    @Test func trackerFallsBackOnPromptRightAfter() {
        let t0 = Date(timeIntervalSince1970: 100)
        var late = QuestionAnswerTracker()
        late.sent(session: "s", answers: ["Q": ["A"]], at: t0)
        let lateResult = late.waitingForInput(session: "s", at: t0.addingTimeInterval(60))
        #expect(!lateResult && late.path == .allowWithAnswers)
        var soon = QuestionAnswerTracker()
        soon.sent(session: "s", answers: ["Q": ["A"]], at: t0)
        let soonResult = soon.waitingForInput(session: "s", at: t0.addingTimeInterval(3))
        #expect(soonResult && soon.path == .denyWithAnswer)
    }

    @Test func claudePostToolUseCarriesTheResultText() {
        let payload = try! JSONDecoder().decode(JSONValue.self, from: Data(#"{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"AskUserQuestion","tool_response":{"answers":{"Q":"SQLite"}}}"#.utf8))
        let event = AgentHookNormalizer.normalize(payload, source: .claudeCode)
        #expect(event?.detail?.contains("SQLite") == true)
    }
}
