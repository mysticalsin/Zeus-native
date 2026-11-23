import Foundation
import Testing
@testable import ZeusCore

@Suite struct PremiumSpokenMomentTests {
    private func isolated() -> UserDefaults {
        let name = "zeus.premium-spoken.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aFreshCountdownStaysSilentUntilTheSettingIsOn() {
        let defaults = isolated()
        #expect(PremiumSpokenMoment.isEnabled(.recordingCountdown, defaults: defaults) == false)
        #expect(PremiumSpokenMoment.spokenLine(.recordingCountdown, countdown: 3, defaults: defaults) == nil)
        PremiumSpokenMoment.setEnabled(.recordingCountdown, true, defaults: defaults)
        #expect(PremiumSpokenMoment.spokenLine(.recordingCountdown, countdown: 3, defaults: defaults) == "Three.")
        #expect(PremiumSpokenMoment.spokenLine(.recordingCountdown, countdown: 2, defaults: defaults) == "Two.")
        #expect(PremiumSpokenMoment.spokenLine(.recordingCountdown, countdown: 1, defaults: defaults) == "One.")
        #expect(PremiumSpokenMoment.spokenLine(.recordingCountdown, countdown: 0, defaults: defaults) == "Recording.")
        #expect(PremiumSpokenMoment.spokenLine(.recordingCountdown, countdown: 4, defaults: defaults) == nil)
        PremiumSpokenMoment.setEnabled(.recordingCountdown, false, defaults: defaults)
        #expect(PremiumSpokenMoment.spokenLine(.recordingCountdown, countdown: 3, defaults: defaults) == nil)
    }

    @Test func notesReadyAndASavedRecordingSpeakUntilTheSettingIsOff() {
        let defaults = isolated()
        #expect(PremiumSpokenMoment.spokenLine(.notesReady, defaults: defaults) == "Notes are ready.")
        #expect(PremiumSpokenMoment.spokenLine(.recordingSaved, defaults: defaults) == "Saved.")
        PremiumSpokenMoment.setEnabled(.notesReady, false, defaults: defaults)
        PremiumSpokenMoment.setEnabled(.recordingSaved, false, defaults: defaults)
        #expect(PremiumSpokenMoment.spokenLine(.notesReady, defaults: defaults) == nil)
        #expect(PremiumSpokenMoment.spokenLine(.recordingSaved, defaults: defaults) == nil)
    }

    @Test func eachMomentHasAVisibleVoiceSetting() {
        let titles = PremiumSpokenMoment.allCases.map(\.settingTitle)
        #expect(Set(titles).count == titles.count)
        for moment in PremiumSpokenMoment.allCases {
            #expect(!moment.settingTitle.isEmpty)
            #expect(!moment.settingDetail.isEmpty)
            #expect(moment.settingKey.hasPrefix("voice.speak"))
        }
        #expect(PremiumSpokenMoment.recordingCountdown.settingTitle == "Speak the recording countdown")
        #expect(PremiumSpokenMoment.notesReady.settingTitle == "Speak when notes are ready")
        #expect(PremiumSpokenMoment.recordingSaved.settingTitle == "Speak when a recording is saved")
        #expect(PremiumSpokenMoment.recordingCountdown.defaultEnabled == false)
        #expect(PremiumSpokenMoment.notesReady.defaultEnabled == true)
        #expect(PremiumSpokenMoment.recordingSaved.defaultEnabled == true)
    }

    @Test func turningOneSettingOffSilencesOnlyThatMoment() {
        let defaults = isolated()
        PremiumSpokenMoment.setEnabled(.notesReady, false, defaults: defaults)
        #expect(PremiumSpokenMoment.spokenLine(.notesReady, defaults: defaults) == nil)
        #expect(PremiumSpokenMoment.spokenLine(.recordingSaved, defaults: defaults) == "Saved.")
        #expect(PremiumSpokenMoment.line(.notesReady, enabled: false) == nil)
        #expect(PremiumSpokenMoment.line(.recordingSaved, enabled: true) == "Saved.")
    }
}
