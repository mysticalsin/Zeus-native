import Foundation
import Testing
@testable import ZeusCore

@Suite struct ZeusDatesTests {
    // 31 Oct 2026 12:00 UTC is 9 Aban 1405 in the Persian calendar.
    let date = Date(timeIntervalSince1970: 1_793_448_000)
    let persian = Locale(identifier: "en_IR@calendar=persian")

    @Test func gregorianWhenForcedEvenOnAPersianMac() {
        let text = ZeusDates.string(date, template: "EEEEdMMMM", followSystem: false, base: persian)
        #expect(text.contains("October"))
        #expect(text.contains("31"))
        #expect(!text.contains("Aban"))
    }

    @Test func followsTheSystemCalendarWhenAsked() {
        let text = ZeusDates.string(date, template: "EEEEdMMMM", followSystem: true, base: persian)
        #expect(text.contains("Aban"))
    }

    @Test func unsetPreferenceIsGregorian() {
        let suite = "zeus.dates.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ZeusDates.followsSystem(defaults) == false)
        defaults.set(false, forKey: ZeusDates.followSystemKey)
        #expect(ZeusDates.followsSystem(defaults) == false)
        defaults.set(true, forKey: ZeusDates.followSystemKey)
        #expect(ZeusDates.followsSystem(defaults) == true)
    }

    @Test func calendarIsGregorian() {
        var base = Calendar(identifier: .persian); base.timeZone = TimeZone(identifier: "UTC")!
        #expect(ZeusDates.calendar(followSystem: false, base: base).identifier == .gregorian)
        #expect(ZeusDates.calendar(followSystem: true, base: base).identifier == .persian)
    }
}
