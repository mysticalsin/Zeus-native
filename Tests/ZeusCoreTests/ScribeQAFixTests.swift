import Foundation
import Testing
@testable import ZeusCore

@Suite("Scribe QA fixes")
struct ScribeQAFixTests {
    // MARK: Checkpoint pacing

    @Test func checkpointGateWritesFirstSegmentAtOnceAndCoalescesTheRest() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var gate = ScribeCheckpointGate(interval: 1)
        let first = gate.segmentAccepted(now: t0)
        #expect(first)
        gate.wrote(success: true, now: t0)
        #expect(!gate.flushDue)
        let coalesced = gate.segmentAccepted(now: t0.addingTimeInterval(0.4))
        #expect(!coalesced)
        #expect(gate.flushDue)
        let later = gate.segmentAccepted(now: t0.addingTimeInterval(1.2))
        #expect(later)
    }

    @Test func failedCheckpointWriteStaysDueUntilItSucceeds() {
        let t0 = Date(timeIntervalSince1970: 2_000)
        var gate = ScribeCheckpointGate(interval: 1)
        let accepted = gate.segmentAccepted(now: t0)
        #expect(accepted)
        gate.wrote(success: false, now: t0)
        #expect(gate.flushDue)
        gate.wrote(success: true, now: t0.addingTimeInterval(2))
        #expect(!gate.flushDue)
        gate.reset()
        #expect(gate.lastWrite == nil)
    }

    // MARK: Recap notes

    @Test func noteIsNilWhenNothingWentWrong() {
        #expect(ScribeRecapNote.compose(issues: [], stoppedEarly: nil, notesIssue: nil) == nil)
        #expect(ScribeRecapNote.badge(for: nil) == nil)
    }

    @Test func stoppedEarlyNoteSaysWhyAndThatItWasSaved() throws {
        let note = try #require(ScribeRecapNote.compose(issues: [], stoppedEarly: "No microphone input.", notesIssue: nil))
        #expect(note.hasPrefix(ScribeRecapNote.stoppedEarlyPrefix))
        #expect(note.contains("No microphone input."))
        #expect(note.contains("saved"))
        #expect(ScribeRecapNote.badge(for: note)?.contains("stopped early") == true)
    }

    @Test func stoppedEarlyWithoutReasonStillReads() throws {
        let note = try #require(ScribeRecapNote.compose(issues: [], stoppedEarly: "  ", notesIssue: nil))
        #expect(note.hasPrefix("Recording stopped early."))
    }

    @Test func issuesAndNotesIssueAreKept() throws {
        let note = try #require(ScribeRecapNote.compose(issues: ["A.", "B."], stoppedEarly: nil, notesIssue: "Only the transcript was saved."))
        #expect(note.contains("may be missing speech"))
        #expect(note.contains("A. B."))
        #expect(note.hasSuffix("Only the transcript was saved."))
        #expect(ScribeRecapNote.badge(for: note)?.contains("incomplete") == true)
    }

    @Test func checkpointNoteKeepsEarlierReasonsAndSaysNotesAreMissing() throws {
        let note = try #require(ScribeRecapNote.compose(
            issues: [], stoppedEarly: "No microphone input.", notesIssue: ScribeRecapNote.checkpointNote
        ))
        #expect(note.hasPrefix(ScribeRecapNote.stoppedEarlyPrefix))
        #expect(note.hasSuffix(ScribeRecapNote.checkpointNote))
        #expect(ScribeRecapNote.badge(for: ScribeRecapNote.checkpointNote)?.contains("incomplete") == true)
    }

    // MARK: Cloud disclosure

    @Test func onlyCloudEnginesAreDisclosed() throws {
        for kind in TranscriptionEngineKind.allCases {
            let text = ScribeCloudDisclosure.text(for: kind)
            #expect((text != nil) == kind.isCloud)
        }
        let eleven = try #require(ScribeCloudDisclosure.text(for: .elevenLabs))
        let openAI = try #require(ScribeCloudDisclosure.text(for: .openAI))
        #expect(eleven.contains("ElevenLabs"))
        #expect(openAI.contains("OpenAI"))
    }

    // MARK: System-audio stall

    @Test func stallLevelsFollowSilence() {
        #expect(ScribeSystemStall.level(silentSeconds: 0) == .ok)
        #expect(ScribeSystemStall.level(silentSeconds: ScribeSystemStall.warningAfter - 0.1) == .ok)
        #expect(ScribeSystemStall.level(silentSeconds: ScribeSystemStall.warningAfter) == .warning)
        #expect(ScribeSystemStall.level(silentSeconds: ScribeSystemStall.lostAfter) == .lost)
        #expect(ScribeSystemStall.level(silentSeconds: .infinity) == .ok)
        #expect(ScribeSystemStall.level(silentSeconds: .nan) == .ok)
    }

    // MARK: Wording

    @Test func micCopyDescribesActualMicrophoneUse() {
        #expect(ScribeMicCallText.sharedNotice.contains("Zeus keeps recording it"))
        #expect(ScribeMicCallText.recapLine.contains("excluded after another app used it"))
    }

    // MARK: Permanent delete

    private func makeStore() throws -> (ScribeMeetingStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scribe-qa-\(UUID().uuidString)", isDirectory: true)
        return (ScribeMeetingStore(directory: root.appendingPathComponent("meetings", isDirectory: true)), root)
    }

    private func record(id: UUID = UUID(), dismissedAt: Date? = nil) -> ScribeMeetingRecord {
        ScribeMeetingRecord(
            id: id, title: "Standup", endedAt: Date(timeIntervalSince1970: 1_000), duration: 60,
            notes: ScribeMeetingNotes(summary: "S", privateNotes: "secret"),
            transcript: [], dismissedAt: dismissedAt
        )
    }

    @Test func deleteRemovesTheFileAndItsContent() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = record()
        try store.save(saved)
        let file = store.directory.appendingPathComponent(saved.fileName)
        #expect(FileManager.default.fileExists(atPath: file.path))
        try store.delete(id: saved.id)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(store.loadAll().records.isEmpty)
    }

    @Test func deleteAlsoRemovesADismissedMeeting() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = record(dismissedAt: Date())
        try store.save(saved)
        try store.delete(id: saved.id)
        #expect(store.loadAll().records.isEmpty)
    }

    @Test func deleteKeepsOtherMeetingsAndToleratesAMissingFile() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let keep = record()
        let drop = record()
        try store.save(keep)
        try store.save(drop)
        try store.delete(id: drop.id)
        try store.delete(id: drop.id)
        #expect(store.loadAll().records.map(\.id) == [keep.id])
    }

    @Test func deleteWithoutAFolderIsNotAnError() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.delete(id: UUID())
    }
}
