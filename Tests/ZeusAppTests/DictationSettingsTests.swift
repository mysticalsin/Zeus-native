import Foundation
import Testing
@testable import Zeus

/// P0 item C (QA7, Tony 3 Nov 23:58): "it should insert by default". Releasing the dictation key
/// must type straight into the focused field; the preview card is opt-in.
@MainActor
@Suite("Dictation settings defaults")
struct DictationSettingsTests {
    @Test func previewBeforeInsertDefaultsToFalse() {
        let suite = "zeus.dictation.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = DictationSettings(defaults: defaults)
        #expect(settings.previewBeforeInsert == false)
    }

    @Test func previewBeforeInsertStaysTrueOncePersisted() {
        // A person who turned the preview card back on keeps it on across restarts: the new
        // default only applies to a Mac that has never set the key.
        let suite = "zeus.dictation.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "dictation.preview")

        let settings = DictationSettings(defaults: defaults)
        #expect(settings.previewBeforeInsert == true)
    }
}
