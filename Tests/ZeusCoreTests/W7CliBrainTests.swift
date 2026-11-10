import Foundation
import Testing
@testable import ZeusCore

@Suite("W7 watch observation")
struct W7CliBrainTests {
    private func gone(_ needle: String) -> ZeusWatch {
        ZeusWatch(label: "doc", trigger: .windowGone(titleContains: needle))
    }

    @Test func unobservedWindowsNeverFireGone() {
        let mac = FakeMacSnapshot(frontApp: "Finder", openTitles: ["Finder"], windowsObserved: false)
        let result = ZeusWatchEvaluator.evaluate(gone("Report.pdf"), mac: mac)
        #expect(!result.fired)
    }

    @Test func observedAbsenceFiresGone() {
        let mac = FakeMacSnapshot(frontApp: "Finder", openTitles: ["Finder"], windowsObserved: true)
        let result = ZeusWatchEvaluator.evaluate(gone("Report.pdf"), mac: mac)
        #expect(result.fired)
    }

    @Test func observedPresenceDoesNotFireGone() {
        let mac = FakeMacSnapshot(frontApp: "Finder", openTitles: ["Finder", "Report.pdf"], windowsObserved: true)
        let result = ZeusWatchEvaluator.evaluate(gone("Report.pdf"), mac: mac)
        #expect(!result.fired)
    }

    @Test func unobservedStillMatchesShows() {
        let mac = FakeMacSnapshot(openTitles: ["Preview"], windowsObserved: false)
        let watch = ZeusWatch(label: "p", trigger: .windowShows(titleContains: "Preview"))
        let result = ZeusWatchEvaluator.evaluate(watch, mac: mac)
        #expect(result.fired)
    }
}
