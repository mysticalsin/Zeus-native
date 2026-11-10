import Foundation
import Testing
@testable import ZeusCore

/// Codex round 6 fixes: preview focus handoff, monotonic slide advance, no mid-use Automation prompt.
@Suite("Round 6 fixes")
struct Round6FixTests {
    final class Frontmost: @unchecked Sendable {
        var sequence: [String?]
        var reads = 0
        init(_ sequence: [String?]) { self.sequence = sequence }
        func read() -> String? {
            defer { reads += 1 }
            return sequence[min(reads, sequence.count - 1)]
        }
    }

    @MainActor @Test func handoffWaitsForTheTargetApp() async {
        let front = Frontmost(["app.zeus.mac", "app.zeus.mac", "com.apple.mail"])
        let ok = await FrontmostHandoff.waitUntilFrontmost(target: "com.apple.mail", current: front.read, attempts: 5, sleep: {})
        #expect(ok)
    }

    @MainActor @Test func handoffGivesUpInsteadOfTypingIntoZEUS() async {
        let front = Frontmost(["app.zeus.mac"])
        let ok = await FrontmostHandoff.waitUntilFrontmost(target: "com.apple.mail", current: front.read, attempts: 3, sleep: {})
        #expect(!ok)
        let none = await FrontmostHandoff.waitUntilFrontmost(target: nil, current: front.read, sleep: {})
        #expect(!none)
    }

    let deck = PresenterDeck(app: .keynote, name: "d", slides: [
        SlideNotes(number: 1, notes: "one two"),        // words 0-1
        SlideNotes(number: 2, notes: "three four"),     // words 2-3
        SlideNotes(number: 3, notes: "five six"),       // words 4-5
    ])

    @Test func advancesOneSlideAtATimeAfterConfirmation() {
        var advancer = SlideAdvancer(current: 1)
        #expect(advancer.next(forWord: 0, in: deck) == nil)
        #expect(advancer.next(forWord: 4, in: deck) == 2)     // jumped ahead: still one step
        #expect(advancer.next(forWord: 5, in: deck) == nil)   // waiting for the app
        advancer.confirm()
        #expect(advancer.shown == 2)
        #expect(advancer.next(forWord: 4, in: deck) == 3)
        advancer.confirm()
        #expect(advancer.shown == 3)
    }

    @Test func neverGoesBackAndRetriesAfterAFailure() {
        var advancer = SlideAdvancer(current: 2)
        #expect(advancer.next(forWord: 0, in: deck) == nil)   // an earlier partial never moves it back
        #expect(advancer.shown == 2)
        #expect(advancer.next(forWord: 4, in: deck) == 3)
        advancer.failed()
        #expect(advancer.shown == 2 && advancer.failures == 1)
        #expect(advancer.next(forWord: 5, in: deck) == 3)     // retried
        advancer.confirm()
        #expect(advancer.shown == 3 && advancer.failures == 0)
        #expect(SlideAdvancer(current: nil).shown == nil)
    }

    @Test func automationIsNeverAskedMidUse() {
        #expect(AutomationGate.message(.granted, app: "Keynote") == nil)
        #expect(AutomationGate.message(.notAsked, app: "Keynote")?.contains("Settings > Permissions") == true)
        #expect(AutomationGate.message(.denied, app: "PowerPoint")?.contains("PowerPoint") == true)
        #expect(AutomationGate.message(.appNotRunning, app: "Keynote") == "Open your presentation in Keynote first.")
    }
}
