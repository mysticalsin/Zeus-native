import Foundation
import Testing
@testable import ZeusCore

@Suite("Notch stop all")
struct NotchStopAllTests {
    func run(_ id: String, _ origin: SupervisedOrigin, _ status: AgentRunState) -> SupervisedRun {
        SupervisedRun(id: id, origin: origin, status: status)
    }

    @Test func activeStartedAndHookedRunsAreHalted() {
        let runs = [
            run("browser", .started, .working),
            run("claude", .hooked, .working),
            run("codex", .hooked, .stalled),
            run("gemini", .hooked, .needsYou),
            run("done", .hooked, .done),
            run("idle", .started, .idle),
            run("failed", .hooked, .failed),
        ]
        let plan = NotchStopAll.plan(runs, handlers: ["browser"])
        #expect(plan.halted == ["browser", "claude", "codex", "gemini"])
        #expect(plan.callHandlers == ["browser"])
        #expect(plan.interrupt == ["claude", "codex", "gemini"])
    }

    @Test func aStartedRunWithoutAHandlerIsMarkedAndNotInterrupted() {
        let plan = NotchStopAll.plan([run("demo", .started, .working)], handlers: [])
        #expect(plan.halted == ["demo"])
        #expect(plan.callHandlers.isEmpty)
        #expect(plan.interrupt.isEmpty)
    }

    @Test func aHookedRunWithAHandlerIsNotAlsoInterrupted() {
        let plan = NotchStopAll.plan([run("research", .hooked, .working)], handlers: ["research"])
        #expect(plan.callHandlers == ["research"])
        #expect(plan.interrupt.isEmpty)
    }

    @Test func voiceStopIsOffUntilAsked() {
        #expect(!NotchStopAll.matchesVoice("stop all agents", enabled: false))
        #expect(!NotchStopAll.matchesVoice("stop", enabled: false))
        #expect(!NotchStopAll.matchesVoice("stop", enabled: true))
        #expect(!NotchStopAll.matchesVoice("stop browsing", enabled: true))
        #expect(!NotchStopAll.matchesVoice("please stop all agents", enabled: true))
        #expect(NotchStopAll.matchesVoice("Stop all agents.", enabled: true))
        #expect(NotchStopAll.matchesVoice("halt all", enabled: true))
        #expect(NotchStopAll.matchesVoice("stop the agents", enabled: true))
    }

    @Test func interruptBytesGoOnlyToATerminalDevice() {
        #expect(NotchStopAll.interruptDevice("/dev/ttys003") == "/dev/ttys003")
        #expect(NotchStopAll.interruptDevice("/dev/pts/4") == "/dev/pts/4")
        #expect(NotchStopAll.interruptDevice("/tmp/ttys003") == nil)
        #expect(NotchStopAll.interruptDevice("/dev/ttys003;rm") == nil)
        #expect(NotchStopAll.interruptDevice("/dev/tty/../etc") == nil)
        #expect(NotchStopAll.interruptDevice(nil) == nil)
        #expect(NotchStopAll.interruptDevice("") == nil)
    }
}
