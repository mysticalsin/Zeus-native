import Testing
import ZeusCore

@Suite("Automation Allow plan")
struct AutomationAllowPlanTests {
    private typealias P = AutomationAllowPlan
    private let music = P.Target(id: "music", name: "Music")
    private let spotify = P.Target(id: "spotify", name: "Spotify")
    private let keynote = P.Target(id: "keynote", name: "Keynote")
    private let powerpoint = P.Target(id: "ppt", name: "PowerPoint")
    private var all: [P.Target] { [music, spotify, keynote, powerpoint] }

    @Test func allowMoreWithOnlyAnAllowedAppOpenAsksNothingAndNamesTheOthers() {
        // The reported case: Music is open and already allowed, the rest are closed.
        let plan = P.plan(targets: all, access: ["music": .allowed], running: ["music"])
        #expect(plan.ask.isEmpty)
        #expect(plan.message == "Open Spotify, Keynote or PowerPoint, then press Allow more.")
        #expect(!plan.opensAutomationPane)
    }

    @Test func allowMoreAsksOnlyTheRunningAppsThatAreNotYetAllowed() {
        let plan = P.plan(targets: all, access: ["music": .allowed], running: ["music", "spotify"])
        #expect(plan.ask == ["spotify"])
        #expect(plan.message == nil)
    }

    @Test func firstAllowWithNothingOpenSaysToOpenAnApp() {
        let plan = P.plan(targets: all, access: [:], running: [])
        #expect(plan.ask.isEmpty)
        #expect(plan.message == "Open Music, Spotify, Keynote or PowerPoint, then press Allow.")
    }

    @Test func aRefusedRunningAppOpensTheAutomationPaneInsteadOfAskingAgain() {
        let plan = P.plan(targets: all, access: ["music": .allowed, "spotify": .refused], running: ["music", "spotify"])
        #expect(plan.ask.isEmpty)
        #expect(plan.message == "Turn on Zeus for Spotify in Automation.")
        #expect(plan.opensAutomationPane)
    }

    @Test func aRefusedAppAlongsideAnAskableOneIsAskedFirstThenSentToTheCheckbox() {
        let plan = P.plan(targets: all, access: ["spotify": .refused], running: ["spotify", "keynote"])
        #expect(plan.ask == ["keynote"])
        #expect(plan.refused == [spotify])
        #expect(!plan.opensAutomationPane)
        let after = P.afterAsking(targets: [keynote], granted: ["keynote": true], alreadyRefused: plan.refused)
        #expect(after.message == "Turn on Zeus for Spotify in Automation.")
        #expect(after.opensAutomationPane)
    }

    @Test func nothingToDoWhenEveryAppIsAllowed() {
        let access = Dictionary(uniqueKeysWithValues: all.map { ($0.id, P.Access.allowed) })
        #expect(P.plan(targets: all, access: access, running: ["music"]) == P.Plan())
    }

    @Test func anAppThatDeclinedTheSheetSendsThePersonToSystemSettings() {
        let after = P.afterAsking(targets: [spotify, keynote], granted: ["spotify": false, "keynote": true], alreadyRefused: [])
        #expect(after.message == "Turn on Zeus for Spotify in Automation.")
        #expect(after.opensAutomationPane)
        #expect(P.afterAsking(targets: [spotify], granted: ["spotify": true], alreadyRefused: []) == P.Plan())
    }

    @Test func namesJoinReadably() {
        #expect(P.list([], joiner: "or") == "")
        #expect(P.list(["A"], joiner: "or") == "A")
        #expect(P.list(["A", "B"], joiner: "and") == "A and B")
        #expect(P.list(["A", "B", "C"], joiner: "or") == "A, B or C")
    }
}
