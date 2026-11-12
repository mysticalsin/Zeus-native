import Foundation
import Testing
@testable import ZeusCore

/// Invitee names, speaker labels and per-turn voices are saved with the meeting file, so after a relaunch the
/// recap still offers invite names and "Remember this voice". Synthetic data only.
@Suite struct ScribeSpeakerPersistenceTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("scribe-speakers-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("meetings", isDirectory: true)
    }

    private func vector(_ seed: Float) -> [Float] {
        (0..<ScribeVoiceEmbedding.wespeakerDimension).map { sin(seed + Float($0) * 0.1) }
    }

    private func turns() -> [ScribeTurnEmbedding] {
        [ScribeTurnEmbedding(segmentID: "sys-0", source: .system,
                             embedding: ScribeVoiceEmbedding(kind: .wespeaker, vector: vector(1)), duration: 4.5),
         ScribeTurnEmbedding(segmentID: "mic-1", source: .microphone,
                             embedding: ScribeVoiceEmbedding(kind: .handBuilt, vector: [0.25, -0.5, 1]), duration: 2)]
    }

    private func record(id: UUID, attendees: [String], voices: [ScribeTurnEmbedding]) -> ScribeMeetingRecord {
        let session = ScribeSessionID(rawValue: id)
        let segments = [
            ScribeTranscriptSegment(id: "mic-1", session: session, speaker: .you, start: 0, end: 2, text: "Hello.", isFinal: true),
            ScribeTranscriptSegment(id: "sys-0", session: session, speaker: .participant("Marie Dubois"), start: 2, end: 6,
                                    text: "Hi, it is Marie.", isFinal: true),
        ]
        return ScribeMeetingRecord(id: id, title: "Sync", endedAt: Date(timeIntervalSince1970: 1_700_000_000), duration: 6,
                                   notes: ScribeMeetingNotes(), transcript: segments,
                                   attendees: ScribeAttendeeNames.clean(attendees), turnVoices: voices.map(ScribeMeetingRecord.TurnVoice.init))
    }

    @Test func namesAndVoicesComeBackAfterAReload() throws {
        let store = ScribeMeetingStore(directory: directory())
        let id = UUID()
        try store.save(record(id: id, attendees: ["Marie Dubois", "Paul Roy"], voices: turns()))
        let loaded = try #require(store.loadAll().records.first)
        #expect(loaded.attendeeNames == ["Marie Dubois", "Paul Roy"])
        #expect(loaded.turnEmbeddings == turns())
        #expect(loaded.segments(session: ScribeSessionID(rawValue: id)).map(\.speaker) == [.you, .participant("Marie Dubois")])
    }

    @Test func theFileIsOwnerOnly() throws {
        let folder = directory()
        let store = ScribeMeetingStore(directory: folder)
        let value = record(id: UUID(), attendees: ["Marie"], voices: turns())
        try store.save(value)
        let attributes = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(value.fileName).path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func aMeetingWithoutNamesOrVoicesWritesNeitherKey() throws {
        let folder = directory()
        let store = ScribeMeetingStore(directory: folder)
        let value = record(id: UUID(), attendees: [], voices: [])
        try store.save(value)
        let text = try String(contentsOf: folder.appendingPathComponent(value.fileName), encoding: .utf8)
        #expect(!text.contains("turnVoices") && !text.contains("attendees"))
        let loaded = try #require(store.loadAll().records.first)
        #expect(loaded.attendeeNames.isEmpty && loaded.turnEmbeddings.isEmpty)
    }

    @Test func aFileSavedBeforeThisChangeStillLoads() throws {
        let folder = directory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID()
        let json = """
        {"version":1,"id":"\(id.uuidString)","title":"Old","endedAt":"2023-11-14T22:13:20Z","duration":5,"summary":"","decisions":[],
         "actionItems":[],"privateNotes":"","transcript":[]}
        """
        try json.write(to: folder.appendingPathComponent(ScribeMeetingRecord.fileName(for: id)), atomically: true, encoding: .utf8)
        let result = ScribeMeetingStore(directory: folder).loadAll()
        #expect(result.failures.isEmpty)
        let loaded = try #require(result.records.first)
        #expect(loaded.attendeeNames.isEmpty && loaded.turnEmbeddings.isEmpty)
    }

    @Test func damagedVoiceBytesAreDroppedNotTrusted() {
        var value = record(id: UUID(), attendees: [], voices: turns())
        value.turnVoices?[0].vector = Data([1, 2, 3])
        value.turnVoices?[1].vector = Data(repeating: 0xFF, count: 8) // NaN
        #expect(value.turnEmbeddings.isEmpty)
    }

    @Test func emailAddressesAreNeverSavedAsNames() {
        let value = record(id: UUID(), attendees: ["marie@example.com", "Marie Dubois"], voices: [])
        #expect(value.attendeeNames == ["Marie Dubois"])
    }
}
