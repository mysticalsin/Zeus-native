import Foundation

/// `Chat.swift` names this value. This slice does not compile `Brain.swift`, which needs CoreGraphics.
public struct Exchange: Codable, Equatable, Sendable {
    public let user: String
    public let assistant: String
    public init(user: String, assistant: String) {
        self.user = user
        self.assistant = assistant
    }
}

/// Oracle for the Chat tab inside the bar. The table is the transcript table plus the page
/// events: a tap, a history selection, New chat, and Copy never open a window.
@main
struct ChatBarPageHost {
    static func main() {
        var failures: [String] = []
        func check(_ ok: Bool, _ message: String) {
            if !ok { failures.append(message) }
        }

        checkChrome(check)
        checkMotion(check)
        checkPresentation(check)
        checkHistory(check)
        checkSave(check)
        checkTransitions(check)
        checkEdges(check)
        checkSource(check)

        if failures.isEmpty {
            print("chat bar page holds")
            return
        }
        for failure in failures.prefix(80) { print(failure) }
        if failures.count > 80 { print("… \(failures.count - 80) more") }
        print("\(failures.count) failures")
        exit(1)
    }

    static func checkChrome(_ check: (Bool, String) -> Void) {
        check(ChatBarPage.listWidth == 270, "list width is 270")
        check(ChatBarPage.emptyTitle == "New conversation", "empty title")
        check(ChatBarPage.emptyDetail == "Chats stay in History on this Mac.", "empty detail")
        check(ChatBarPage.newChatTitle == "New chat", "new chat label")
        check(ChatBarPage.composerPlaceholder == "Message Zeus", "composer placeholder constant")
        check(ChatBarPage.selectionOpacity == 0.12, "selection is the 12% wash")
        check(ChatBarPage.idleRowOpacity == 0, "an unselected history row has no card fill")
        check(ChatBarPage.sectionOrder == ["Pinned", "Today", "Yesterday", "Previous 7 days", "Older"], "section order")
        check(ChatBarPage.historyRowsUseStatusColor == false, "history rows do not use a status color")
        check(ChatBarPage.newChatAccentFill == false, "New chat is a quiet pill")

        let idle = ChatBarPage.composer(draft: "", sendingHere: false, busyElsewhere: false)
        check(idle.placeholder == "Message Zeus", "idle placeholder")
        check(idle.showsStop == false && idle.sendEnabled == false && idle.sendQuiet, "blank draft keeps Send quiet")

        let spaces = ChatBarPage.composer(draft: " \n\t ", sendingHere: false, busyElsewhere: false)
        check(spaces.sendEnabled == false && spaces.sendQuiet && spaces.showsStop == false, "whitespace draft keeps Send quiet")

        let ready = ChatBarPage.composer(draft: "Show a sample", sendingHere: false, busyElsewhere: false)
        check(ready.sendEnabled && ready.sendQuiet == false && ready.showsStop == false, "a non-empty draft can send")
        check(ready.placeholder == "Message Zeus", "ready placeholder")

        let streaming = ChatBarPage.composer(draft: "Stop this", sendingHere: true, busyElsewhere: false)
        check(streaming.showsStop && streaming.sendEnabled == false && streaming.sendQuiet, "Stop replaces Send while this chat streams")

        let elsewhere = ChatBarPage.composer(draft: "Show a sample", sendingHere: false, busyElsewhere: true)
        check(elsewhere.sendEnabled == false && elsewhere.showsStop == false, "Send waits while another chat is answering")
        check(elsewhere.placeholder == "Zeus is answering in another chat", "the other-chat placeholder stays")
    }

    static func checkMotion(_ check: (Bool, String) -> Void) {
        let reduced = ChatBarPage.motion(reduceMotion: true)
        check(reduced.offset == 0 && reduced.scale == 1, "Reduce Motion requests zero offset and scale 1")
        let moving = ChatBarPage.motion(reduceMotion: false)
        check(moving.offset == 8 && moving.scale == 0.985, "motion keeps the existing 8 pt page crossfade")
    }

    static func checkPresentation(_ check: (Bool, String) -> Void) {
        let user = UUID()
        let agent = UUID()
        let failed = UUID()
        let stopped = UUID()
        let sample = """
        # Title

        - One

        ```
        print(1)
        ```
        """
        let messages = [
            ChatMessage(id: user, role: .user, text: "Show a sample"),
            ChatMessage(id: agent, role: .assistant, text: sample),
            ChatMessage(id: failed, role: .assistant, text: "# Not a heading\n\n```\nprint(1)\n```", failed: true),
            ChatMessage(id: stopped, role: .assistant, text: "Stopped."),
        ]
        let shown = ChatBarPage.present(messages: messages, sending: false)
        check(shown.status == .settled, "a finished conversation is settled")
        check(shown.lines.count == 4, "every stored line is shown")
        check(shown.lines[0].role == .person && shown.lines[0].parsesAsMarkdown == false, "a person line is a bubble, not markdown")
        check(shown.lines[1].role == .agent && shown.lines[1].parsesAsMarkdown, "a settled agent line uses markdown")
        check(shown.lines[1].id == agent.uuidString, "the agent line id stays the message id")
        let parsed = MarkdownBlock.parse(sample)
        check(parsed.contains { if case .heading = $0 { return true }; return false }, "the sample parses as a heading")
        check(parsed.contains { if case .list = $0 { return true }; return false }, "the sample parses as a list")
        check(parsed.contains { if case .code(_, let text) = $0 { return text == "print(1)" }; return false }, "the sample code block body is print(1)")
        check(shown.lines[2].role == .failed && shown.lines[2].parsesAsMarkdown == false, "a failed line is plain, even when it looks like markdown")
        check(shown.lines[2].text == "# Not a heading\n\n```\nprint(1)\n```", "a failed line keeps the raw text")
        check(shown.lines[3].role == .stopped && shown.lines[3].parsesAsMarkdown == false, "Stopped. is plain text")
        check(shown.lines[3].text == "Stopped.", "the model’s stopped sentence is kept")

        let waiting = ChatBarPage.present(
            messages: [ChatMessage(id: user, role: .user, text: "Stop this"), ChatMessage(id: agent, role: .assistant, text: "")],
            sending: true
        )
        check(waiting.status == .streaming, "an empty reply while sending is streaming")
        check(waiting.lines.last?.role == .agent && waiting.lines.last?.text.isEmpty == true, "the open agent line is empty before the first token")
        check(waiting.lines.last?.parsesAsMarkdown == false, "the waiting line is not markdown")

        let hard = ChatBarPage.present(
            messages: [ChatMessage(role: .assistant, text: "The reply did not finish.", failed: true)],
            sending: false
        )
        check(hard.status == .failed && hard.lines.first?.role == .failed, "a thrown failure is a failed line")
        check(hard.lines.first?.parsesAsMarkdown == false, "a thrown failure is not markdown")

        let empty = ChatBarPage.present(messages: [], sending: false)
        check(empty.status == .idle && empty.lines.isEmpty, "an empty conversation is idle")

        let stoppedWord = ChatBarPage.present(
            messages: [ChatMessage(role: .assistant, text: HubTranscriptNotice.stopped.storedLabel)],
            sending: false
        )
        check(stoppedWord.lines.first?.role == .stopped, "the notice Stopped is a stopped line")

        let failedStop = ChatBarPage.present(
            messages: [ChatMessage(role: .assistant, text: "Stopped.", failed: true)],
            sending: false
        )
        check(failedStop.lines.first?.role == .failed, "a failed Stopped. stays a failed line")
    }

    static func checkHistory(_ check: (Bool, String) -> Void) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let start = calendar.startOfDay(for: now)
        func chat(_ id: UUID, at date: Date, pinned: Bool = false) -> ChatConversation {
            ChatConversation(
                id: id,
                createdAt: date,
                messages: [ChatMessage(role: .user, text: "note", date: date)],
                pinned: pinned
            )
        }
        let pinned = UUID()
        let todayNew = UUID()
        let todayOld = UUID()
        let yesterday = UUID()
        let weekEdge = UUID()
        let older = UUID()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: start)!
        let items = [
            chat(todayOld, at: start),
            chat(older, at: weekAgo.addingTimeInterval(-1)),
            chat(pinned, at: now.addingTimeInterval(-40 * 86_400), pinned: true),
            chat(yesterday, at: start.addingTimeInterval(-1)),
            chat(weekEdge, at: weekAgo),
            chat(todayNew, at: now),
        ]
        let sections = ChatBarPage.history(items, now: now, calendar: calendar)
        check(sections.map(\.title) == ["Pinned", "Today", "Yesterday", "Previous 7 days", "Older"], "headings that have chats, empty ones skipped, in order")
        check(sections.first { $0.title == "Pinned" }?.ids == [pinned], "a pin stays pinned even when it is old")
        check(sections.first { $0.title == "Today" }?.ids == [todayNew, todayOld], "today is newest first")
        check(sections.first { $0.title == "Yesterday" }?.ids == [yesterday], "one second before today is yesterday")
        check(sections.first { $0.title == "Previous 7 days" }?.ids == [weekEdge], "the seventh day is still this week")
        check(sections.first { $0.title == "Older" }?.ids == [older], "one second before the seventh day is older")

        let only = ChatBarPage.history([chat(todayNew, at: now), chat(older, at: weekAgo.addingTimeInterval(-1))], now: now, calendar: calendar)
        check(only.map(\.title) == ["Today", "Older"], "empty Yesterday and Previous 7 days are not drawn")
        check(ChatBarPage.history([], now: now, calendar: calendar).isEmpty, "no chats means no headings")
    }

    static func checkSave(_ check: (Bool, String) -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-chat-bar-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChatStore(root: root)
        let empty = ChatConversation(title: "An unsent draft")
        try? ChatBarPage.save(empty, to: store)
        let filesAfterEmpty = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        check(filesAfterEmpty.isEmpty, "an empty conversation is not written")

        let user = "Show a sample"
        let reply = """
        # Title

        - One

        ```
        print(1)
        ```
        """
        var saved = ChatConversation(createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        saved.append(ChatMessage(role: .user, text: user, date: saved.createdAt))
        saved.append(ChatMessage(role: .assistant, text: reply, date: saved.createdAt.addingTimeInterval(1)))
        do { try ChatBarPage.save(saved, to: store) } catch {
            check(false, "save threw \(error)")
            return
        }
        let url = root.appendingPathComponent("\(saved.id.uuidString).json")
        check(FileManager.default.fileExists(atPath: url.path), "the file name is the conversation id json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            check(false, "the file is the existing conversation JSON")
            return
        }
        check(object["messages"] != nil && object["lines"] == nil, "the JSON is a conversation, not a transcript blob")
        let text = String(decoding: data, as: UTF8.self)
        check(text.contains(user) && text.contains("print(1)"), "the file contains the question and the code")
        let again = ChatStore(root: root).all().first
        check(again?.id == saved.id && again?.messages.map(\.text) == [user, reply], "a second store reads that conversation back")

        let link = UUID()
        let visual = ChatConversation(title: "A linked explanation", visualExplanationID: link)
        try? ChatBarPage.save(visual, to: store)
        let reloaded = ChatStore(root: root).all().first { $0.id == visual.id }
        check(reloaded?.visualExplanationID == link && reloaded?.messages.isEmpty == true, "a visual-only link still uses the same JSON file")
    }

    static func checkTransitions(_ check: (Bool, String) -> Void) {
        let fresh = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
        let selected = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
        var visited = 0
        for status in HubTranscriptStatus.allCases {
            for event in events(selected: selected) {
                visited += 1
                let before = seed(status)
                let effect = ChatBarPage.reduce(before, event, lineID: fresh)
                let want = oracle(before, event, lineID: fresh)
                let name = "\(status.storedLabel) + \(eventName(event))"
                check(effect.opensWindow == false, "\(name) does not open a window")
                check(effect.writes == want.writes, "\(name) writes \(want.writes) got \(effect.writes)")
                check(effect.sendToModel == want.send, "\(name) send \(want.send)")
                check(effect.stopModel == want.stop, "\(name) stop \(want.stop)")
                check(effect.state.transcript.status == want.status, "\(name) status \(want.status.storedLabel) got \(effect.state.transcript.status.storedLabel)")
                check(effect.state.showsNewChatForm == want.form, "\(name) form")
                check(effect.state.selectedID == want.selected, "\(name) selection")
                check(effect.state.composerFocused == want.focused, "\(name) focus")
                check(effect.state.draft == want.draft, "\(name) draft")
                check(effect.log == want.log, "\(name) log \(String(describing: effect.log)) != \(String(describing: want.log))")
                check(sameLines(effect.state.transcript.lines, want.lines), "\(name) lines \(describe(effect.state.transcript.lines)) != \(describe(want.lines))")
            }
        }
        check(visited == HubTranscriptStatus.allCases.count * events(selected: selected).count, "every status and event pair was visited")
    }

    static func checkEdges(_ check: (Bool, String) -> Void) {
        let person = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let fresh = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
        var waiting = ChatBarState(
            transcript: HubTranscript(
                status: .streaming,
                lines: [HubTranscriptLine(id: person, role: .person, text: "Stop this")]
            ),
            selectedID: nil,
            showsNewChatForm: false,
            draft: "",
            composerFocused: false
        )
        let stopped = ChatBarPage.reduce(waiting, .stop, lineID: fresh)
        check(stopped.opensWindow == false && stopped.stopModel && stopped.writes, "stop before the first token saves")
        check(stopped.state.transcript.status == .settled, "stop before the first token settles")
        check(stopped.state.transcript.lines.last?.role == .stopped, "stop before the first token is a stopped line")
        check(stopped.state.transcript.lines.last?.text == "Stopped", "stop before the first token says Stopped")
        check(stopped.state.transcript.lines.last?.failed == false, "Stopped is not a failed line")
        check(stopped.log == ChatBarLog(source: "chat", stage: "stopped", detail: "current"), "stop before the first token logs stopped")

        waiting.transcript.lines.append(HubTranscriptLine(id: fresh, role: .agent, text: ""))
        let stoppedEmpty = ChatBarPage.reduce(waiting, .stop, lineID: fresh)
        check(stoppedEmpty.state.transcript.lines.count == 2, "an empty agent line is replaced, not duplicated")
        check(stoppedEmpty.state.transcript.lines.last?.role == .stopped, "an empty agent line becomes Stopped")
        check(stoppedEmpty.state.transcript.lines.last?.id == fresh, "the waiting line keeps its id")

        var streaming = waiting
        streaming.transcript.lines[1].text = "# Title"
        streaming.transcript.lines[1].role = .agent
        let first = ChatBarPage.reduce(streaming, .delta("- One"), lineID: fresh)
        let second = ChatBarPage.reduce(first.state, .delta("# Title\n\n- One\n\n```\nprint(1)\n```"), lineID: UUID())
        check(first.writes == false && second.writes == false, "deltas do not write")
        check(second.state.transcript.lines.count == 2, "deltas replace the open agent line")
        check(second.state.transcript.lines.last?.id == fresh, "the agent line id is stable while tokens arrive")
        check(second.state.transcript.lines.last?.text.contains("print(1)") == true, "the second delta is the whole line")

        let opened = ChatBarPage.reduce(streaming, .newChat, lineID: fresh)
        let closed = ChatBarPage.reduce(opened.state, .newChat, lineID: fresh)
        check(opened.opensWindow == false && opened.state.showsNewChatForm, "New chat opens the form")
        check(closed.opensWindow == false && closed.state.showsNewChatForm == false, "New chat again closes the form")
        check(sameLines(closed.state.transcript.lines, streaming.transcript.lines), "New chat does not drop the transcript")

        var forming = streaming
        forming.showsNewChatForm = true
        let picked = UUID()
        let selected = ChatBarPage.reduce(forming, .selectHistory(picked), lineID: fresh)
        check(selected.opensWindow == false && selected.state.selectedID == picked && selected.state.showsNewChatForm == false, "a history click selects and stays in the bar")

        let tapped = ChatBarPage.reduce(forming, .transcriptTap, lineID: fresh)
        check(tapped.opensWindow == false && tapped.state.composerFocused, "a transcript click focuses the composer")
        check(sameLines(tapped.state.transcript.lines, forming.transcript.lines), "a transcript click does not change the lines")

        let waitingMessages = [
            ChatMessage(id: person, role: .user, text: "Stop this"),
            ChatMessage(id: fresh, role: .assistant, text: ""),
        ]
        let stored = ChatBarPage.transcript(messages: waitingMessages, sending: true)
        check(stored.status == .streaming, "a live empty reply is streaming")
        let fromModel = ChatBarPage.reduce(
            ChatBarState(transcript: stored, selectedID: nil, showsNewChatForm: false, draft: "", composerFocused: false),
            .stop,
            lineID: fresh
        )
        check(fromModel.stopModel && fromModel.state.transcript.lines.last?.text == "Stopped", "Stop on the live transcript says Stopped")
        check(fromModel.state.transcript.lines.last?.id == fresh, "Stop keeps the waiting line’s id")
    }

    struct Want {
        var status: HubTranscriptStatus
        var lines: [HubTranscriptLine]
        var writes: Bool
        var log: ChatBarLog?
        var send: Bool
        var stop: Bool
        var focused: Bool
        var form: Bool
        var selected: UUID?
        var draft: String
    }

    static func oracle(_ state: ChatBarState, _ event: ChatBarEvent, lineID: UUID) -> Want {
        var want = Want(
            status: state.transcript.status,
            lines: state.transcript.lines,
            writes: false,
            log: nil,
            send: false,
            stop: false,
            focused: state.composerFocused,
            form: state.showsNewChatForm,
            selected: state.selectedID,
            draft: state.draft
        )
        switch event {
        case .send(let text):
            let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if spoken.isEmpty {
                want.log = ChatBarLog(source: "chat", stage: "idle", detail: "current")
            } else if state.transcript.status != .streaming {
                want.status = .streaming
                want.lines.append(HubTranscriptLine(id: lineID, role: .person, text: spoken))
                want.writes = true
                want.send = true
                want.draft = ""
            }
        case .delta(let text):
            guard state.transcript.status == .streaming else { break }
            want.lines = replaceAgent(want.lines, id: lineID, role: .agent, text: text, failed: false)
        case .finish(let text):
            guard state.transcript.status == .streaming else { break }
            let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !spoken.isEmpty {
                want.status = .settled
                want.lines = replaceAgent(want.lines, id: lineID, role: .agent, text: spoken, failed: false)
                want.writes = true
                want.log = ChatBarLog(source: "chat", stage: "settled", detail: "current")
            } else if let open = want.lines.last, open.role == .agent, !open.failed, !open.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                want.status = .settled
                want.writes = true
                want.log = ChatBarLog(source: "chat", stage: "settled", detail: "current")
            }
        case .finishEmpty:
            guard state.transcript.status == .streaming else { break }
            want.status = .failed
            want.lines = replaceAgent(want.lines, id: lineID, role: .failed, text: "No answer came back.", failed: true)
            want.writes = true
            want.log = ChatBarLog(source: "chat", stage: "failed", detail: "current")
        case .stop:
            guard state.transcript.status == .streaming else { break }
            want.stop = true
            want.status = .settled
            want.writes = true
            if let open = want.lines.last, open.role == .agent, !open.failed, !open.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                want.log = ChatBarLog(source: "chat", stage: "settled", detail: "current")
            } else {
                want.lines = replaceAgent(want.lines, id: lineID, role: .stopped, text: "Stopped", failed: false)
                want.log = ChatBarLog(source: "chat", stage: "stopped", detail: "current")
            }
        case .failure(let text):
            guard state.transcript.status == .streaming else { break }
            want.status = .failed
            want.lines = replaceAgent(want.lines, id: lineID, role: .failed, text: text, failed: true)
            want.writes = true
            want.log = ChatBarLog(source: "chat", stage: "failed", detail: "current")
        case .transcriptTap:
            want.focused = true
            want.log = ChatBarLog(source: "chat", stage: "tab", detail: "chat")
        case .selectHistory(let id):
            want.selected = id
            want.form = false
            want.log = ChatBarLog(source: "chat", stage: "select", detail: "current")
        case .newChat:
            want.form.toggle()
        case .copy:
            want.log = ChatBarLog(source: "chat", stage: "copy", detail: "current")
        }
        return want
    }

    static func replaceAgent(_ lines: [HubTranscriptLine], id: UUID, role: HubLineRole, text: String, failed: Bool) -> [HubTranscriptLine] {
        var lines = lines
        if let index = lines.indices.last, lines[index].role == .agent, !lines[index].failed {
            lines[index].role = role
            lines[index].text = text
            lines[index].failed = failed
            return lines
        }
        lines.append(HubTranscriptLine(id: id, role: role, text: text, failed: failed))
        return lines
    }

    static func seed(_ status: HubTranscriptStatus) -> ChatBarState {
        let person = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let agent = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        var lines: [HubTranscriptLine] = []
        if status != .idle {
            lines.append(HubTranscriptLine(id: person, role: .person, text: "Show a sample"))
        }
        if status == .streaming {
            lines.append(HubTranscriptLine(id: agent, role: .agent, text: "# Title"))
        } else if status == .failed {
            lines.append(HubTranscriptLine(id: agent, role: .failed, text: "No answer came back.", failed: true))
        } else if status == .settled {
            lines.append(HubTranscriptLine(id: agent, role: .agent, text: "Done already"))
        }
        return ChatBarState(
            transcript: HubTranscript(id: person, status: status, lines: lines),
            selectedID: nil,
            showsNewChatForm: false,
            draft: "draft",
            composerFocused: false
        )
    }

    static func events(selected: UUID) -> [ChatBarEvent] {
        [
            .send("Show a sample"),
            .send(""),
            .send(" \n\t "),
            .send("  Show a sample  "),
            .delta("# Title"),
            .delta(""),
            .finish("# Title\n\n- One\n\n```\nprint(1)\n```"),
            .finish(""),
            .finish("   "),
            .finishEmpty,
            .stop,
            .failure("The reply did not finish."),
            .failure("# Not a heading"),
            .failure("```\nprint(1)\n```"),
            .failure(""),
            .transcriptTap,
            .selectHistory(selected),
            .newChat,
            .copy("print(1)"),
        ]
    }

    static func eventName(_ event: ChatBarEvent) -> String {
        switch event {
        case .send(let text): "send(\(text.debugDescription))"
        case .delta(let text): "delta(\(text.debugDescription))"
        case .finish(let text): "finish(\(text.debugDescription))"
        case .finishEmpty: "finishEmpty"
        case .stop: "stop"
        case .failure(let text): "failure(\(text.debugDescription))"
        case .transcriptTap: "transcriptTap"
        case .selectHistory: "selectHistory"
        case .newChat: "newChat"
        case .copy: "copy"
        }
    }

    static func sameLines(_ got: [HubTranscriptLine], _ want: [HubTranscriptLine]) -> Bool {
        got.count == want.count && zip(got, want).allSatisfy {
            $0.id == $1.id && $0.role == $1.role && $0.text == $1.text && $0.failed == $1.failed
        }
    }

    static func describe(_ lines: [HubTranscriptLine]) -> String {
        lines.map { "\($0.role.storedLabel):\($0.text):\($0.failed)" }.joined(separator: " | ")
    }

    static func checkSource(_ check: (Bool, String) -> Void) {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/Zeus/TopBar/ChatPage.swift")
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            check(false, "ChatPage.swift could not be read")
            return
        }
        check(!source.contains("openWindow"), "the page does not open the floating window")
        for name in ["Claude", "Codex", "Gemini", "Cursor", "iTerm"] {
            check(!source.contains(name), "the page does not name \(name)")
        }
        check(source.contains("ChatBarPage.reduce"), "the view asks the page table before it acts")
        check(source.contains("HubTranscriptView"), "the transcript uses the hub transcript view")
    }
}
