import Foundation
import Testing
@testable import ZeusCore

@Suite struct ZeusTagParserTests {
    @Test func leadingPointIsParsedAndStripped() {
        let result = ZeusTagParser.parse("[POINT:640,320:export button:screen2] it's the export button, top right.")
        #expect(result.tags == [.point(PointTarget(x: 640, y: 320, label: "export button", screen: 2))])
        #expect(result.spokenText == "it's the export button, top right.")
    }

    @Test func pointNone() {
        let result = ZeusTagParser.parse("[POINT:none] nothing on screen for that.")
        #expect(result.tags == [.point(nil)])
        #expect(result.spokenText == "nothing on screen for that.")
    }

    @Test func pointWithoutLabelButWithScreen() {
        let result = ZeusTagParser.parse("[POINT:10, 20:screen1] here")
        #expect(result.tags == [.point(PointTarget(x: 10, y: 20, label: nil, screen: 1))])
    }

    @Test func trailingClickyStyleTagStillWorks() {
        let result = ZeusTagParser.parse("click the blue button. [POINT:100,200:save]")
        #expect(result.tags == [.point(PointTarget(x: 100, y: 200, label: "save"))])
        #expect(result.spokenText == "click the blue button.")
    }

    @Test func highlight() {
        let result = ZeusTagParser.parse("[HIGHLIGHT:10,20,300,40:toolbar] that's the toolbar")
        #expect(result.tags == [.highlight(HighlightTarget(x: 10, y: 20, width: 300, height: 40, label: "toolbar"))])
    }

    @Test func actionWithBracketsInsideJSON() {
        let reply = #"[ACTION:{"type":"browser.type","target":{"text":"Search [all]"},"text":"zeus ]","submit":true}] searching now"#
        let result = ZeusTagParser.parse(reply)
        guard case .action(let action) = result.tags.first else {
            Issue.record("expected an action, got \(result.tags)")
            return
        }
        #expect(action.kind == .browserType)
        #expect(action.payload["text"] == .string("zeus ]"))
        #expect(result.spokenText == "searching now")
    }

    @Test func multipleLeadingTags() {
        let result = ZeusTagParser.parse(#"[POINT:1,2] [ACTION:{"type":"panel.open","which":"dust"}] opening dust"#)
        #expect(result.tags.count == 2)
        #expect(result.spokenText == "opening dust")
    }

    @Test func unknownActionTypeIsDroppedFromSpeech() {
        let result = ZeusTagParser.parse(#"[ACTION:{"type":"system.format_disk"}] ok"#)
        #expect(result.tags.isEmpty)
        #expect(result.spokenText == "ok")
    }

    @Test func plainTextAndOrdinaryBracketsAreUntouched() {
        let result = ZeusTagParser.parse("[note] this is fine")
        #expect(result.tags.isEmpty)
        #expect(result.spokenText == "[note] this is fine")
    }

    @Test func streamEmitsTagBeforeAnyText() {
        var parser = ZeusTagStreamParser()
        var outputs: [ZeusTagStreamParser.Output] = []
        for chunk in ["[PO", "INT:5", "0,60:menu]", " it's ", "in the menu. [PO", "INT:none]"] {
            outputs += parser.feed(chunk)
        }
        outputs += parser.finish()
        #expect(outputs.first == .tag(.point(PointTarget(x: 50, y: 60, label: "menu"))))
        let spoken = outputs.compactMap { output -> String? in
            if case .text(let text) = output { return text }
            return nil
        }.joined()
        #expect(spoken.trimmingCharacters(in: .whitespaces) == "it's in the menu.")
        #expect(outputs.last == .tag(.point(nil)))
    }

    @Test func streamWithNoTags() {
        var parser = ZeusTagStreamParser()
        let outputs = parser.feed("hello there") + parser.finish()
        #expect(outputs == [.text("hello there")])
    }
}

@Suite struct EnvelopeTests {
    @Test func nativeMessagingRoundTrip() throws {
        let request = BridgeRequest(id: "r-1", type: "browser.read", params: ["tab": .string("active")])
        let json = try JSONEncoder().encode(request)
        var buffer = try NativeMessagingFrame.encode(json) + NativeMessagingFrame.encode(json)
        buffer.append(contentsOf: [0x05, 0x00]) // start of a third, incomplete frame
        let messages = NativeMessagingFrame.decode(&buffer)
        #expect(messages.count == 2)
        #expect(try JSONDecoder().decode(BridgeRequest.self, from: messages[0]) == request)
        #expect(buffer.count == 2)
    }

    @Test func oversizedFrameIsRejected() {
        let big = Data(count: NativeMessagingFrame.maxHostToChromeBytes + 1)
        #expect(throws: NativeMessagingFrame.FrameError.self) { try NativeMessagingFrame.encode(big) }
    }

    @Test func claudeCodeHookOutputShape() throws {
        let output = HookDecision(id: "x", decision: .deny, reason: "Denied by voice in ZEUS").claudeCodeOutput()
        let data = try JSONEncoder().encode(JSONValue.object(output))
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded["hookSpecificOutput"]?["permissionDecision"] == .string("deny"))
        #expect(decoded["hookSpecificOutput"]?["hookEventName"] == .string("PreToolUse"))
    }

    @Test func riskAssessment() {
        #expect(CommandRisk.assess(tool: "Bash", input: .object(["command": .string("rm -rf dist")])) == .high)
        #expect(CommandRisk.assess(tool: "Bash", input: .object(["command": .string("git push origin main")])) == .medium)
        #expect(CommandRisk.assess(tool: "Bash", input: .object(["command": .string("ls -la")])) == .low)
        #expect(CommandRisk.assess(tool: "Read", input: nil) == .low)
    }
}

@Suite struct SpeechTextTests {
    @Test func splitsSentencesAsTheyStream() {
        var splitter = SentenceSplitter()
        var sentences: [String] = []
        for chunk in ["it's the blue but", "ton. click it", " once! then wait", " 3.5 seconds"] {
            sentences += splitter.feed(chunk)
        }
        #expect(sentences == ["it's the blue button.", "click it once!"])
        #expect(splitter.flush() == "then wait 3.5 seconds")
    }

    @Test func approvalWords() {
        #expect(ApprovalPhrases.verdict(for: "OK.") == .allow)
        #expect(ApprovalPhrases.verdict(for: "yeah go ahead") == .allow)
        #expect(ApprovalPhrases.verdict(for: "no") == .deny)
        #expect(ApprovalPhrases.verdict(for: "no, don't do it") == .deny)
        #expect(ApprovalPhrases.verdict(for: "okay no wait") == .deny)
        #expect(ApprovalPhrases.verdict(for: "what is this command going to delete exactly") == nil)
        #expect(ApprovalPhrases.verdict(for: "hmm") == nil)
    }

    @Test func permissionRequestOutput() {
        #expect(HookDecision(id: "1", decision: .ask).claudePermissionRequestOutput() == nil)
        let allow = HookDecision(id: "1", decision: .allow).claudePermissionRequestOutput()
        #expect(allow?["hookSpecificOutput"]?["decision"]?["behavior"] == .string("allow"))
        let deny = HookDecision(id: "1", decision: .deny, reason: "nope").claudePermissionRequestOutput()
        #expect(deny?["hookSpecificOutput"]?["decision"]?["message"] == .string("nope"))
    }
}

@Suite struct SocketTests {
    @Test func requestAndReplyOverUnixSocket() throws {
        let path = NSTemporaryDirectory() + "zeus-test-\(UUID().uuidString.prefix(8)).sock"
        let server = UnixSocketServer(path: path) { line, reply in
            reply(Data("echo:".utf8) + line)
        }
        try server.start()
        defer { server.stop() }
        let reply = UnixSocket.request(path: path, payload: Data("hi".utf8), expectReply: true, timeout: 2)
        #expect(reply == Data("echo:hi".utf8))
    }

    @Test func missingServerReturnsNilQuickly() {
        let start = Date()
        let reply = UnixSocket.request(path: "/tmp/zeus-nobody-\(UUID().uuidString.prefix(6)).sock",
                                       payload: Data("x".utf8), expectReply: true, timeout: 5)
        #expect(reply == nil)
        #expect(Date().timeIntervalSince(start) < 0.5)
    }
}

@Suite struct ChromeBridgeContractTests {
    @Test func tabContextDecodesWithoutPageText() throws {
        let json = Data(#"{"url":"https://example.com","title":"Example"}"#.utf8)
        let tab = try JSONDecoder().decode(TabContext.self, from: json)
        #expect(tab.text == nil && tab.controls == nil && tab.title == "Example")
    }

    @Test func bridgeResponseCarriesExtensionErrors() throws {
        let json = Data(#"{"id":"1","ok":false,"error":{"code":"sensitive_field","message":"Please type it yourself."}}"#.utf8)
        let response = try JSONDecoder().decode(BridgeResponse.self, from: json)
        #expect(response.ok == false && response.error?.code == "sensitive_field")
    }

    @Test func panelOpenActionParses() {
        let result = ZeusTagParser.parse(#"[ACTION:{"type":"panel.open","which":"chatgpt","prompt":"Plan my week"}] Asking ChatGPT."#)
        guard case .action(let action)? = result.tags.first else { Issue.record("no action"); return }
        #expect(action.kind == .panelOpen)
        #expect(action.payload["prompt"]?.stringValue == "Plan my week")
        #expect(action.payload["which"]?.stringValue == "chatgpt")
    }

    @Test func jsonValueAccessors() {
        let value: JSONValue = .object(["a": .array([.bool(true)])])
        #expect(value["a"]?.arrayValue?.first?.boolValue == true)
    }
}
