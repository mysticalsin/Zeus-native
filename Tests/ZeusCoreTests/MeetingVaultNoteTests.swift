import Foundation
import Testing
@testable import ZeusCore

@Suite("Meeting vault note")
struct MeetingVaultNoteTests {
    private let date = Date(timeIntervalSince1970: 1_793_475_612)
    private let utc = TimeZone(identifier: "UTC")!
    private let meeting = UUID(uuidString: "4F6A1C20-8B3E-4D11-9A70-2C5E8B1D0A44")!

    @Test func aSavedRecapKeepsTheMeetingIdentifierAndLeavesPrivateNotesOut() {
        let notes = ScribeMeetingNotes(
            summary: "We chose Tuesday.",
            decisions: ["Ship the recap\nwithout the recording"],
            actionItems: [ScribeActionItem(text: "Send the note", done: true)],
            privateNotes: "do-not-export-this-private-line")
        let text = MeetingVaultNote.document(id: meeting, title: " Tuesday sync ", notes: notes, created: date, timeZone: utc)
        #expect(text.contains("source: zeus-meeting\nrecord: \(meeting.uuidString)\n"))
        #expect(text.contains("# Tuesday sync\n"))
        #expect(text.contains("We chose Tuesday."))
        #expect(text.contains("- Ship the recap without the recording"))
        #expect(text.contains("- [x] Send the note"))
        #expect(!text.contains("do-not-export-this-private-line"))
        #expect(!text.contains("privateNotes"))
        #expect(!text.localizedCaseInsensitiveContains(".m4a"))
        #expect(!text.contains("/Users/"))
    }

    @Test func anEmptyRecapStillNamesTheMeetingAndSkipsPrivateNotes() {
        let notes = ScribeMeetingNotes(privateNotes: "still private")
        let text = MeetingVaultNote.document(id: meeting, title: "   ", notes: notes, created: date, timeZone: utc)
        #expect(text.contains("# Meeting notes\n\nMeeting notes\n"))
        #expect(text.contains("record: \(meeting.uuidString)"))
        #expect(!text.contains("still private"))
    }
}
