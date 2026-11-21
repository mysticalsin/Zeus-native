import Foundation
import Testing
import ZeusCore

/// Behaviour of the private log and the sentences a person actually reads.
/// Keys are synthetic. Nothing here is a credential.
@Suite("Private logging")
struct PrivateLoggingTests {
    private static let prefixedSecret = "sk-" + String(repeating: "ab", count: 8)
    private static let xiSecret = "xi-" + String(repeating: "q", count: 12)
    private static let aiStyle = "AIza" + String(repeating: "x", count: 20)
    private static let hexSecret = String(repeating: "ab", count: 16)
    private static let base64Secret = String(repeating: "Zm9v+/", count: 8) + "=="
    private static let homePath = "/Users/ada/Meetings/plan.wav"

    @Test func redactRemovesPrefixedKeysAndLongRuns() {
        let line = "saw \(Self.prefixedSecret) and \(Self.xiSecret) then \(Self.aiStyle)"
        let redacted = PrivateLogText.redact(line)
        #expect(redacted == "saw [redacted] and [redacted] then [redacted]")
        #expect(!redacted.contains(Self.prefixedSecret))
        #expect(!redacted.contains(Self.xiSecret))
        #expect(!redacted.contains(Self.aiStyle))

        #expect(PrivateLogText.redact("blob \(Self.base64Secret) end") == "blob [redacted] end")
        #expect(PrivateLogText.redact("id \(Self.hexSecret) ok") == "id [redacted] ok")
        #expect(!PrivateLogText.redact(Self.base64Secret).contains("Zm9v"))
        #expect(!PrivateLogText.redact(Self.hexSecret).contains("ab"))
    }

    @Test func redactLeavesOrdinaryTextAndShortTokens() {
        let prose = "Couldn't save this meeting. It is still here. Try again."
        #expect(PrivateLogText.redact(prose) == prose)
        #expect(PrivateLogText.redact("") == "")
        #expect(PrivateLogText.redact("sk-short") == "sk-short")
        #expect(PrivateLogText.redact("xi-tiny") == "xi-tiny")
        #expect(PrivateLogText.redact("AIza1234") == "AIza1234")
        #expect(PrivateLogText.redact(String(repeating: "ab", count: 15)) == String(repeating: "ab", count: 15))
        let meetingID = "123E4567-E89B-12D3-A456-426614174000"
        #expect(PrivateLogText.redact(meetingID) == meetingID)
        let once = PrivateLogText.redact("prefix \(Self.prefixedSecret) suffix")
        #expect(PrivateLogText.redact("prefix \(Self.prefixedSecret) suffix") == once)
    }

    @Test func keyAndPermissionSentencesAreDistinctAndFixed() {
        let specific = [
            ShownFailure.missingKey,
            ShownFailure.revokedKey,
            ShownFailure.microphoneDenied,
            ShownFailure.speechDenied,
            ShownFailure.fileDenied,
        ]
        #expect(Set(specific).count == specific.count)
        let generic = [
            ShownFailure.meetingSave,
            ShownFailure.meetingNotes,
            ShownFailure.dictationFile,
            ShownFailure.engine("Speech"),
        ]
        for sentence in specific {
            #expect(!generic.contains(sentence))
            #expect(!sentence.contains("/"))
            #expect(!sentence.contains("sk-"))
            #expect(!sentence.contains("xi-"))
            #expect(!sentence.contains("AIza"))
            #expect(!sentence.contains(Self.homePath))
            #expect(sentence.contains("Try again") || sentence.contains("Allow") || sentence.contains("Settings"))
        }
        #expect(ShownFailure.missingKey == "An API key is missing. Add it in Settings, then try again.")
        #expect(ShownFailure.revokedKey == "That API key was revoked. Add a new one in Settings, then try again.")
        #expect(ShownFailure.microphoneDenied == "The microphone is off for Zeus. Turn it on in System Settings, then try again.")
        #expect(ShownFailure.speechDenied == "Speech recognition is off for Zeus. Turn it on in System Settings, then try again.")
        #expect(ShownFailure.fileDenied == "Zeus isn't allowed to use that file. Allow access, then try again.")
    }

    @Test func missingAndRevokedKeysHaveTheirOwnSentences() {
        let missing = CloudTranscriptionError.missingKey("Cloud")
        let revoked = CloudTranscriptionError.rejectedKey("Cloud")
        #expect(ShownFailure.notice(for: missing) == .missingKey)
        #expect(ShownFailure.notice(for: revoked) == .revokedKey)
        #expect(ShownFailure.sentence(for: missing, otherwise: ShownFailure.engine("Speech")) == ShownFailure.missingKey)
        #expect(ShownFailure.sentence(for: revoked, otherwise: ShownFailure.engine("Speech")) == ShownFailure.revokedKey)
        let rawMissing = missing.errorDescription ?? ""
        let rawRevoked = revoked.errorDescription ?? ""
        #expect(ShownFailure.missingKey != rawMissing)
        #expect(ShownFailure.revokedKey != rawRevoked)
        #expect(!ShownFailure.missingKey.contains(rawMissing))
        #expect(!ShownFailure.revokedKey.contains(rawRevoked))
    }

    @Test func providerMessagesStayOutOfTheSentenceAndLoseKeyFragmentsInTheLog() {
        let server = CloudTranscriptionError.server("Cloud", "refused \(Self.prefixedSecret)")
        let shown = ShownFailure.sentence(for: server, otherwise: ShownFailure.engine("Speech"))
        #expect(shown == ShownFailure.engine("Speech"))
        #expect(!shown.contains(Self.prefixedSecret))
        #expect(!shown.contains("refused"))
        let logged = ShownFailure.logDetail(server)
        #expect(logged.contains("[redacted]"))
        #expect(!logged.contains(Self.prefixedSecret))

        let relayed = ElevenLabsRealtime.error(type: "transcriber_error", message: "failed \(Self.xiSecret)")
        let relayedShown = ShownFailure.sentence(for: relayed, otherwise: ShownFailure.engine("Speech"))
        #expect(relayedShown == ShownFailure.engine("Speech"))
        #expect(!relayedShown.contains(Self.xiSecret))
        #expect(!relayedShown.contains("failed"))
        let relayedLog = ShownFailure.logDetail(relayed)
        #expect(!relayedLog.contains(Self.xiSecret))
        #expect(relayedLog.contains("[redacted]"))

        let rejected = ElevenLabsRealtime.error(type: "auth_error", message: Self.xiSecret)
        #expect(ShownFailure.sentence(for: rejected, otherwise: ShownFailure.engine("Speech")) == ShownFailure.revokedKey)
        #expect(!ShownFailure.revokedKey.contains(Self.xiSecret))
    }

    @Test func deniedPermissionsEachHaveASentenceAndHideTheSystemText() {
        let file = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileReadNoPermission.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "The file \(Self.homePath) couldn't be opened because you don't have permission."]
        )
        #expect(ShownFailure.notice(for: file) == .fileDenied)
        let fileShown = ShownFailure.sentence(for: file, otherwise: ShownFailure.dictationFile)
        #expect(fileShown == ShownFailure.fileDenied)
        #expect(!fileShown.contains(Self.homePath))
        #expect(!fileShown.contains("ada"))
        #expect(!fileShown.contains("couldn't be opened"))

        let write = CocoaError(.fileWriteNoPermission)
        #expect(ShownFailure.sentence(for: write, otherwise: ShownFailure.meetingSave) == ShownFailure.fileDenied)

        let posix = NSError(domain: NSPOSIXErrorDomain, code: 13, userInfo: [
            NSLocalizedDescriptionKey: "Permission denied: \(Self.homePath)",
        ])
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadUnknown.rawValue, userInfo: [
            NSUnderlyingErrorKey: posix,
            NSLocalizedDescriptionKey: "couldn't read \(Self.homePath)",
        ])
        #expect(ShownFailure.notice(for: wrapped) == .fileDenied)
        #expect(ShownFailure.sentence(for: wrapped, otherwise: ShownFailure.meetingSave) == ShownFailure.fileDenied)

        let microphone = NSError(domain: "NSOSStatusErrorDomain", code: 561017453, userInfo: [
            NSLocalizedDescriptionKey: "permission denied \(Self.homePath)",
        ])
        #expect(ShownFailure.sentence(for: microphone, otherwise: ShownFailure.engine("Speech")) == ShownFailure.microphoneDenied)
        let capture = NSError(domain: "com.apple.coreaudio.avfaudio", code: 561017453, userInfo: [
            NSLocalizedDescriptionKey: "record permission \(Self.homePath)",
        ])
        #expect(ShownFailure.notice(for: capture) == .microphoneDenied)

        let speech = NSError(domain: "kAFAssistantErrorDomain", code: 1700, userInfo: [
            NSLocalizedDescriptionKey: "User denied access to speech recognition",
        ])
        let speechShown = ShownFailure.sentence(for: speech, otherwise: ShownFailure.engine("Speech"))
        #expect(speechShown == ShownFailure.speechDenied)
        #expect(!speechShown.contains("User denied"))
        #expect(ShownFailure.notice(for: NSError(domain: "kAFAssistantErrorDomain", code: 1110)) == nil)

        let unrelated = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadCorruptFile.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "corrupt \(Self.homePath) \(Self.prefixedSecret)",
        ])
        #expect(ShownFailure.sentence(for: unrelated, otherwise: ShownFailure.meetingSave) == ShownFailure.meetingSave)
        let unrelatedLog = ShownFailure.logDetail(unrelated)
        #expect(!unrelatedLog.contains(Self.prefixedSecret))
        #expect(unrelatedLog.contains("[redacted]"))
    }
}
