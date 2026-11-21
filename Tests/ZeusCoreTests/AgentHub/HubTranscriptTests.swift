import Foundation
import Testing
@testable import ZeusCore

/// The transcript machine and the JSON file it writes. The directory is always injected.
@Suite("Hub transcript")
struct HubTranscriptTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-hub-transcript-\(UUID().uuidString)", isDirectory: true)
    }

    private func jsonFiles(in directory: URL) -> [URL] {
        let found = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return found.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private let answer = """
    # Title

    - One

    > Keep it

    ```
    print(1)
    ```
    """

    /// A delta replaces the open agent line and does not write. Finish writes one JSON file.
    /// A second store on that directory is a relaunch and reads the line back.
    @Test func deltaReplacesTheOpenLineAndFinishReadsBack() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(directory.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        let store = HubTranscriptStore(directory: directory)
        #expect(store.directory.standardizedFileURL == directory.standardizedFileURL)
        let id = UUID()
        let personID = UUID()
        let agentID = UUID()
        var transcript = HubTranscript(id: id)

        try HubTranscriptDriver.apply(&transcript, .send, text: "Show a sample", store: store, lineID: personID)
        #expect(transcript.status == .streaming)
        #expect(transcript.lines.map(\.text) == ["Show a sample"])
        #expect(transcript.lines.map(\.role) == [.person])
        #expect(jsonFiles(in: directory).map(\.lastPathComponent) == ["\(id.uuidString).json"])
        let afterSend = try Data(contentsOf: jsonFiles(in: directory)[0])
        #expect(!String(decoding: afterSend, as: UTF8.self).contains("print(1)"))

        try HubTranscriptDriver.apply(&transcript, .delta, text: "# Title", store: store, lineID: agentID)
        #expect(transcript.status == .streaming)
        #expect(transcript.lines.map(\.id) == [personID, agentID])
        #expect(transcript.lines.map(\.text) == ["Show a sample", "# Title"])
        #expect(transcript.lines.map(\.role) == [.person, .agent])
        #expect(try Data(contentsOf: jsonFiles(in: directory)[0]) == afterSend)

        try HubTranscriptDriver.apply(&transcript, .delta, text: answer, store: store, lineID: UUID())
        #expect(transcript.lines.count == 2)
        #expect(transcript.lines[1].id == agentID)
        #expect(transcript.lines[1].text == answer)
        #expect(transcript.lines[1].failed == false)
        #expect(transcript.status == .streaming)
        #expect(jsonFiles(in: directory).count == 1)
        #expect(try Data(contentsOf: jsonFiles(in: directory)[0]) == afterSend)
        #expect(HubTranscriptRendering.render(transcript.lines[1]) == .markdown(MarkdownBlock.parse(answer)))

        try HubTranscriptDriver.apply(&transcript, .finish, text: answer, store: store, lineID: UUID())
        #expect(transcript.status == .settled)
        #expect(transcript.lines[1].id == agentID)
        #expect(transcript.lines[1].text == answer)
        #expect(transcript.lines[1].role == .agent)
        #expect(jsonFiles(in: directory).map(\.lastPathComponent) == ["\(id.uuidString).json"])
        let written = try Data(contentsOf: jsonFiles(in: directory)[0])
        #expect(written != afterSend)
        let raw = String(decoding: written, as: UTF8.self)
        #expect(raw.contains("Show a sample"))
        #expect(raw.contains("print(1)"))

        let relaunched = HubTranscriptStore(directory: directory)
        let loaded = try #require(relaunched.load(id))
        #expect(loaded == transcript)
        #expect(loaded.status == .settled)
        #expect(loaded.lines.map(\.text) == ["Show a sample", answer])
        guard case .markdown(let blocks) = HubTranscriptRendering.render(loaded.lines[1]) else {
            Issue.record("A settled agent line is markdown")
            return
        }
        #expect(blocks == [
            .heading(level: 1, text: "Title"),
            .list(ordered: false, items: [.init(text: "One", depth: 0, number: nil, checked: nil)]),
            .quote("Keep it"),
            .code(language: nil, text: "print(1)"),
        ])
    }

    /// A failed line is stored with `failed` set. The render helper does not parse it as markdown.
    @Test func failedLineIsStoredAndNotRenderedAsMarkdown() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HubTranscriptStore(directory: directory)
        let error = "# Not a heading\n- not a list"
        var transcript = HubTranscript(id: UUID())
        try HubTranscriptDriver.apply(&transcript, .send, text: "Show a sample", store: store, lineID: UUID())
        try HubTranscriptDriver.apply(&transcript, .delta, text: "# Title\n- One", store: store, lineID: UUID())
        try HubTranscriptDriver.apply(&transcript, .failure, text: error, store: store, lineID: UUID())

        #expect(transcript.status == .failed)
        let failed = try #require(transcript.lines.last)
        #expect(transcript.lines.map(\.text) == ["Show a sample", error])
        #expect(failed.role == .failed)
        #expect(failed.failed)
        #expect(HubTranscriptRendering.render(failed) == HubTranscriptPresentation.plain(error))
        let parsed = MarkdownBlock.parse(error)
        #expect(parsed.contains { if case .heading = $0 { true } else { false } })
        #expect(HubTranscriptRendering.render(failed) != .markdown(parsed))
        let flagged = HubTranscriptLine(role: .agent, text: error, failed: true)
        #expect(HubTranscriptRendering.render(flagged) == .plain(error))

        #expect(jsonFiles(in: directory).count == 1)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: jsonFiles(in: directory)[0])) as? [String: Any])
        let lines = try #require(object["lines"] as? [[String: Any]])
        #expect(lines.last?["failed"] as? Bool == true)
        #expect(lines.last?["role"] as? String == "failed")
        #expect(lines.last?["text"] as? String == error)
        let loaded = try #require(HubTranscriptStore(directory: directory).load(transcript.id))
        #expect(loaded.lines.last?.failed == true)
        #expect(loaded.status == .failed)

        let emptyDirectory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: emptyDirectory) }
        let emptyStore = HubTranscriptStore(directory: emptyDirectory)
        var emptyFinish = HubTranscript(id: UUID())
        try HubTranscriptDriver.apply(&emptyFinish, .send, text: "Stop this", store: emptyStore, lineID: UUID())
        try HubTranscriptDriver.apply(&emptyFinish, .finishEmpty, store: emptyStore, lineID: UUID())
        #expect(emptyFinish.status == .failed)
        #expect(emptyFinish.lines.map(\.text) == ["Stop this", HubTranscriptNotice.noAnswer.storedLabel])
        #expect(emptyFinish.lines.last?.role == .failed)
        #expect(emptyFinish.lines.last?.failed == true)
        #expect(HubTranscriptRendering.render(emptyFinish.lines[1]) == .plain(HubTranscriptNotice.noAnswer.storedLabel))
        #expect(jsonFiles(in: emptyDirectory).count == 1)
        let emptyLoaded = try #require(HubTranscriptStore(directory: emptyDirectory).load(emptyFinish.id))
        #expect(emptyLoaded == emptyFinish)
    }

    @Test func emptyConversationIsNotWritten() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HubTranscriptStore(directory: directory)
        try store.write(HubTranscript())
        try store.write(HubTranscript(id: UUID(), status: .settled, lines: [
            HubTranscriptLine(role: .agent, text: "   "),
        ]))
        var transcript = HubTranscript(id: UUID())
        try HubTranscriptDriver.apply(&transcript, .sendBlank, text: "ignored", store: store)
        try HubTranscriptDriver.apply(&transcript, .send, text: " \n\t ", store: store)
        #expect(transcript.status == .idle)
        #expect(transcript.lines.isEmpty)
        #expect(store.load(transcript.id) == nil)
        #expect(jsonFiles(in: directory).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// Every target row, and every pair the table does not list, which must not move.
    @Test func unlistedPairsStayPutAndTheRestOfTheTableHolds() throws {
        let personID = UUID()
        let agentID = UUID()
        let person = HubTranscriptLine(id: personID, role: .person, text: "earlier", failed: false)
        let agent = HubTranscriptLine(id: agentID, role: .agent, text: "partial", failed: false)
        let seed = [person, agent]

        let sent = HubTranscriptMachine.reduce(HubTranscript(), .send, text: "  hello  ", lineID: personID)
        #expect(sent.writes)
        #expect(sent.transcript.status == .streaming)
        #expect(sent.transcript.lines == [HubTranscriptLine(id: personID, role: .person, text: "hello")])

        let idle = HubTranscript(id: UUID(), lines: seed)
        let blank = HubTranscriptMachine.reduce(idle, .send, text: "  ")
        #expect(blank == HubTranscriptEffect(transcript: idle, writes: false))
        let settledBlank = HubTranscriptMachine.reduce(HubTranscript(id: idle.id, status: .settled, lines: seed), .send, text: " ")
        #expect(settledBlank.transcript == HubTranscript(id: idle.id, status: .settled, lines: seed))
        #expect(settledBlank.writes == false)
        let namedBlank = HubTranscriptMachine.reduce(HubTranscript(), .sendBlank, text: "hello")
        #expect(namedBlank.transcript.status == .idle)
        #expect(namedBlank.transcript.lines.isEmpty)
        #expect(namedBlank.writes == false)

        var streaming = HubTranscript(status: .streaming, lines: [person])
        let opened = HubTranscriptMachine.reduce(streaming, .delta, text: "partial", lineID: agentID)
        #expect(opened.writes == false)
        #expect(opened.transcript.status == .streaming)
        #expect(opened.transcript.lines == [person, agent])

        streaming.lines = seed
        let replaced = HubTranscriptMachine.reduce(streaming, .delta, text: "a", lineID: UUID())
        #expect(replaced.writes == false)
        #expect(replaced.transcript.status == .streaming)
        #expect(replaced.transcript.lines == [person, HubTranscriptLine(id: agentID, role: .agent, text: "a")])

        let finished = HubTranscriptMachine.reduce(streaming, .finish, text: " answer ", lineID: UUID())
        #expect(finished.writes)
        #expect(finished.transcript.status == .settled)
        #expect(finished.transcript.lines == [person, HubTranscriptLine(id: agentID, role: .agent, text: "answer")])
        let finishKeepsStreamedText = HubTranscriptMachine.reduce(streaming, .finish, text: " ")
        #expect(finishKeepsStreamedText.writes)
        #expect(finishKeepsStreamedText.transcript.status == .settled)
        #expect(finishKeepsStreamedText.transcript.lines == seed)

        let noAnswer = HubTranscriptMachine.reduce(streaming, .finishEmpty, lineID: UUID())
        #expect(noAnswer.writes)
        #expect(noAnswer.transcript.status == .failed)
        #expect(noAnswer.transcript.lines == [
            person,
            HubTranscriptLine(id: agentID, role: .failed, text: HubTranscriptNotice.noAnswer.storedLabel, failed: true),
        ])
        #expect(HubTranscriptRendering.render(noAnswer.transcript.lines[1]) == .plain(HubTranscriptNotice.noAnswer.storedLabel))

        let stoppedWithText = HubTranscriptMachine.reduce(streaming, .stop)
        #expect(stoppedWithText.writes)
        #expect(stoppedWithText.transcript.status == .settled)
        #expect(stoppedWithText.transcript.lines == seed)
        #expect(HubTranscriptRendering.render(stoppedWithText.transcript.lines[1]) == .markdown(MarkdownBlock.parse("partial")))

        let beforeDelta = HubTranscript(status: .streaming, lines: [person])
        let stopped = HubTranscriptMachine.reduce(beforeDelta, .stop, lineID: agentID)
        #expect(stopped.writes)
        #expect(stopped.transcript.status == .settled)
        #expect(stopped.transcript.lines == [
            person,
            HubTranscriptLine(id: agentID, role: .stopped, text: HubTranscriptNotice.stopped.storedLabel, failed: false),
        ])
        #expect(HubTranscriptRendering.render(stopped.transcript.lines[1]) == .plain(HubTranscriptNotice.stopped.storedLabel))

        let emptyDelta = HubTranscript(status: .streaming, lines: [person, HubTranscriptLine(id: agentID, role: .agent, text: " ")])
        let stoppedEmpty = HubTranscriptMachine.reduce(emptyDelta, .stop, lineID: UUID())
        #expect(stoppedEmpty.transcript.lines.last?.text == HubTranscriptNotice.stopped.storedLabel)
        #expect(stoppedEmpty.transcript.lines.last?.id == agentID)
        #expect(stoppedEmpty.transcript.lines.last?.role == .stopped)

        let failedTurn = HubTranscriptMachine.reduce(streaming, .failure, text: "# boom", lineID: UUID())
        #expect(failedTurn.writes)
        #expect(failedTurn.transcript.status == .failed)
        #expect(failedTurn.transcript.lines == [
            person,
            HubTranscriptLine(id: agentID, role: .failed, text: "# boom", failed: true),
        ])
        #expect(HubTranscriptRendering.render(failedTurn.transcript.lines[1]) == .plain("# boom"))
        let failedBeforeDelta = HubTranscriptMachine.reduce(beforeDelta, .failure, text: "The service had an error", lineID: agentID)
        #expect(failedBeforeDelta.transcript.lines.map(\.text) == ["earlier", "The service had an error"])
        #expect(failedBeforeDelta.transcript.lines.map(\.role) == [.person, .failed])

        let again = HubTranscriptMachine.reduce(finished.transcript, .send, text: "once more", lineID: UUID())
        #expect(again.writes)
        #expect(again.transcript.status == .streaming)
        #expect(again.transcript.lines.map(\.text) == ["earlier", "answer", "once more"])
        #expect(again.transcript.lines.map(\.role) == [.person, .agent, .person])
        let afterFailure = HubTranscriptMachine.reduce(failedTurn.transcript, .send, text: "try once more", lineID: UUID())
        #expect(afterFailure.writes)
        #expect(afterFailure.transcript.status == .streaming)
        #expect(afterFailure.transcript.lines.map(\.text) == ["earlier", "# boom", "try once more"])
        #expect(afterFailure.transcript.lines[1].failed)
        #expect(HubTranscriptRendering.render(HubTranscriptLine(role: .person, text: "# Title")) == .plain("# Title"))

        let changing: Set<String> = [
            "idle send", "settled send", "failed send",
            "streaming delta", "streaming finish", "streaming finishEmpty", "streaming stop", "streaming failure",
        ]
        for status in HubTranscriptStatus.allCases {
            for event in HubTranscriptEvent.allCases {
                let key = "\(status.storedLabel) \(event.storedLabel)"
                guard !changing.contains(key) else { continue }
                let start = HubTranscript(id: personID, status: status, lines: seed)
                let effect = HubTranscriptMachine.reduce(start, event, text: "hello", lineID: agentID)
                #expect(effect.transcript == start, "\(key) is not a table row")
                #expect(effect.writes == false, "\(key) does not write")
            }
        }

        let left = temporaryDirectory()
        let right = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: left)
            try? FileManager.default.removeItem(at: right)
        }
        var owned = HubTranscript(id: UUID())
        try HubTranscriptDriver.apply(&owned, .send, text: "only here", store: HubTranscriptStore(directory: left), lineID: personID)
        #expect(HubTranscriptStore(directory: right).load(owned.id) == nil)
        #expect(jsonFiles(in: right).isEmpty)
        #expect(try #require(HubTranscriptStore(directory: left).load(owned.id)).lines.map(\.text) == ["only here"])
    }
}
