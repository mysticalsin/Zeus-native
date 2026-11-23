import Foundation
import Testing
@testable import ZeusCore

@Suite("Brain capture note")
struct BrainCaptureNoteTests {
    private let date = Date(timeIntervalSince1970: 1_793_475_612)
    private let utc = TimeZone(identifier: "UTC")!

    @Test func theNoteWithoutARecordMatchesTheCaptureShape() {
        let text = BrainCaptureNote.document(title: " Plan\nfor Monday ", body: "\n- call bank\n",
                                              source: "chat reply", created: date, timeZone: utc)
        #expect(text == "---\ntype: capture\nsource: zeus-chatreply\ncreated: 2026-10-31T19:40:12Z\ntags: [zeus, inbox]\n---\n\n# Plan for Monday\n\n- call bank\n")
        #expect(!text.contains("record:"))
    }

    @Test func aMessageIdentifierStaysOnOneFrontMatterLine() {
        let id = "4F6A1C20-8B3E-4D11-9A70-2C5E8B1D0A44"
        let text = BrainCaptureNote.document(title: "Reply", body: "Bring the notes.", source: "chat",
                                              created: date, timeZone: utc, record: id)
        #expect(text.contains("source: zeus-chat\nrecord: \(id)\ncreated:"))
        #expect(text.contains("# Reply\n\nBring the notes.\n"))
    }

    @Test func aPathOrBlankIdentifierIsOmitted() {
        for raw in ["", "   ", "../vault/secret.md", "chat/1", "id with spaces", "line\nbreak", String(repeating: "a", count: 81)] {
            let text = BrainCaptureNote.document(title: "Note", body: "Body", source: "chat",
                                                  created: date, timeZone: utc, record: raw)
            #expect(!text.contains("record:"), "kept an unsafe id: \(raw)")
            #expect(!text.contains("secret"))
            #expect(!text.contains("../"))
        }
        #expect(BrainCaptureNote.token(nil) == nil)
    }
}
