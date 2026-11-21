import Testing
@testable import Zeus

@MainActor
@Suite("Deck notes controller")
struct DeckNotesControllerTests {
    @Test func aRecordingIsStored() {
        let notes = PresenterNotesController()
        notes.noteScreenCapture(shareDetected: false, recordingDetected: true)
        #expect(notes.notedRecording)
    }
}
