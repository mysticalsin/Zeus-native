import Foundation
import Testing
@testable import ZeusCore

@Suite("Voice diagnostic privacy")
struct VoiceLogPrivacyTests {
    @Test func conversationIsMetadataUnlessContentWasExplicitlyEnabled() {
        let transcript = "Meet Jordan at the private studio 🪷"
        let metadata = VoiceLogRecord.contentDescription(transcript, includeContent: false)
        #expect(metadata == "(\(transcript.count) chars)")
        #expect(!metadata.contains("Jordan"))
        #expect(VoiceLogRecord.contentDescription(transcript, includeContent: true) == transcript)
    }

    @Test func providerErrorsAreRedactedBeforeAnySinkCanReadThem() {
        // Generated fixture values, never real provider credentials.
        let secret = "sk-" + String(repeating: "synthetic", count: 4)
        let record = VoiceLogRecord(stage: "error", detail: "Provider refused \(secret); token=synthetic-session at /Users/fixture/Library",
                                    home: "/Users/fixture")
        #expect(!record.detail.contains(secret))
        #expect(!record.detail.contains("synthetic-session"))
        #expect(!record.detail.contains("/Users/fixture"))
        #expect(record.detail.contains("[redacted]") && record.detail.contains("~/Library"))
        let line = record.line(at: Date(timeIntervalSince1970: 0))
        #expect(line.hasSuffix(record.detail))
        #expect(!line.contains(secret))
        let recorder = FlightRecorder(capacity: 1)
        recorder.record("voice", record.stage, record.detail)
        #expect(recorder.events.first?.detail == record.detail)
    }

    @Test func debugContentStillRedactsCredentialsAndCannotForgeAnotherLine() {
        let text = "Bearer " + String(repeating: "fixture", count: 4) + "\r\nforged line"
        let record = VoiceLogRecord(stage: "wake\nforged", detail:
            VoiceLogRecord.contentDescription(text, includeContent: true))
        #expect(record.stage == "wake forged")
        #expect(!record.detail.contains(String(repeating: "fixture", count: 4)))
        #expect(!record.line(at: Date()).contains("\n"))
        #expect(!record.line(at: Date()).contains("\r"))
    }

    @Test func longUntrustedDiagnosticsHaveBoundedStoredFields() {
        let record = VoiceLogRecord(stage: String(repeating: "s", count: 200),
                                    detail: String(repeating: "🪷", count: 20_000))
        #expect(record.stage == "[oversized diagnostic omitted]")
        #expect(record.detail == "[oversized diagnostic omitted]")
        // Discard, rather than publish a truncated credential that evades recognition.
        let oversizedKey = VoiceLogRecord(stage: "error", detail: "sk-" + String(repeating: "x", count: 10_000))
        #expect(!oversizedKey.detail.contains("sk-"))
        let singleGrapheme = "a" + String(repeating: "\u{301}", count: 20_000)
        #expect(singleGrapheme.count == 1)
        #expect(VoiceLogRecord(stage: "error", detail: singleGrapheme).detail == "[oversized diagnostic omitted]")
    }
}
