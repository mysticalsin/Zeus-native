import Testing
@testable import ZeusCore

/// The launch rule in `docs/STEP-ZERO-PROBE-PLAN.md`. No plist, no process list, no clock.
@Suite("Step zero gate")
struct StepZeroGateTests {
    private let now: Int64 = 1_700_000_000

    private func ready() -> StepZeroGate.Facts {
        StepZeroGate.Facts(
            arguments: [StepZeroGate.flag],
            marker: true,
            expiry: now + StepZeroGate.maximumLife,
            now: now,
            seal: .intact,
            responsiblePID: 4242,
            ownPID: 4242,
            parentPID: StepZeroGate.launchdParent,
            serviceName: StepZeroGate.servicePrefix + "1",
            otherZeus: 0,
            qaStart: false,
            onConsole: true,
            unlocked: true
        )
    }

    @Test func theConstantsMatchThePlan() {
        #expect(StepZeroGate.flag == "--" + "step-zero-probe")
        #expect(StepZeroGate.servicePrefix == "application." + "app.zeus.mac.")
        #expect(StepZeroGate.servicePrefix.hasSuffix("."))
        #expect(StepZeroGate.launchdParent == 1)
        #expect(StepZeroGate.maximumLife == 72 * 60 * 60)
        #expect(StepZeroGate.refusalExitCode == 64)
    }

    @Test func noFlagGivesNotRequestedWhateverElseIsTrue() {
        var facts = ready()
        facts.arguments = []
        facts.marker = nil
        facts.expiry = nil
        facts.seal = .broken
        facts.responsiblePID = nil
        facts.parentPID = nil
        facts.serviceName = nil
        facts.otherZeus = nil
        facts.qaStart = true
        facts.onConsole = false
        facts.unlocked = false
        #expect(StepZeroGate.decide(facts) == .notRequested)

        facts.arguments = ["--qa-startup", "root"]
        #expect(StepZeroGate.decide(facts) == .notRequested)

        facts.arguments = [StepZeroGate.flag + "=1"]
        #expect(StepZeroGate.decide(facts) == .notRequested)
    }

    @Test func theFlagWithAnySecondArgumentIsRefused() {
        for extra in ["note", "", StepZeroGate.flag] {
            var facts = ready()
            facts.arguments = [StepZeroGate.flag, extra]
            facts.marker = false
            #expect(StepZeroGate.decide(facts) == .refused(.extraArgument))
        }
        var later = ready()
        later.arguments = ["--other", StepZeroGate.flag]
        #expect(StepZeroGate.decide(later) == .refused(.extraArgument))
    }

    @Test func eachOfTheSevenChecksRefusesAlone() {
        var extra = ready()
        extra.arguments = [StepZeroGate.flag, "note"]
        #expect(StepZeroGate.decide(extra) == .refused(.extraArgument))

        var marker = ready()
        marker.marker = false
        #expect(StepZeroGate.decide(marker) == .refused(.markerMissing))

        var expiry = ready()
        expiry.expiry = now
        #expect(StepZeroGate.decide(expiry) == .refused(.expiryPast))

        var seal = ready()
        seal.seal = .broken
        #expect(StepZeroGate.decide(seal) == .refused(.sealBroken))

        var pid = ready()
        pid.responsiblePID = 4243
        #expect(StepZeroGate.decide(pid) == .refused(.responsiblePIDDiffers))

        var others = ready()
        others.otherZeus = 1
        #expect(StepZeroGate.decide(others) == .refused(.otherZeus))

        var qa = ready()
        qa.qaStart = true
        #expect(StepZeroGate.decide(qa) == .refused(.qaStart))

        var console = ready()
        console.onConsole = false
        #expect(StepZeroGate.decide(console) == .refused(.offConsole))

        var locked = ready()
        locked.unlocked = false
        #expect(StepZeroGate.decide(locked) == .refused(.locked))
    }

    @Test func anExpiryInThePastOrMoreThan72HoursAheadRefuses() {
        var past = ready()
        past.expiry = now - 1
        #expect(StepZeroGate.decide(past) == .refused(.expiryPast))

        var equal = ready()
        equal.expiry = now
        #expect(StepZeroGate.decide(equal) == .refused(.expiryPast))

        var far = ready()
        far.expiry = now + StepZeroGate.maximumLife + 1
        #expect(StepZeroGate.decide(far) == .refused(.expiryTooFar))

        var edge = ready()
        edge.expiry = now + StepZeroGate.maximumLife
        #expect(StepZeroGate.decide(edge) == .run)

        var brief = ready()
        brief.expiry = now + 1
        #expect(StepZeroGate.decide(brief) == .run)
    }

    @Test func aResponsiblePidAParentAndAForeignServiceEachRefuse() {
        var differs = ready()
        differs.responsiblePID = 7
        #expect(StepZeroGate.decide(differs) == .refused(.responsiblePIDDiffers))

        var missing = ready()
        missing.responsiblePID = nil
        #expect(StepZeroGate.decide(missing) == .refused(.responsiblePIDUnreadable))

        for parent: Int32 in [0, 2000] {
            var facts = ready()
            facts.parentPID = parent
            #expect(StepZeroGate.decide(facts) == .refused(.parentNotLaunchd))
        }

        let barePrefix = String(StepZeroGate.servicePrefix.dropLast())
        for name in ["application.app.zeus.other", "APPLICATION.APP.ZEUS.MAC.1", barePrefix, "Zeus"] {
            var facts = ready()
            facts.serviceName = name
            #expect(StepZeroGate.decide(facts) == .refused(.serviceNameOther))
        }

        var prefixed = ready()
        prefixed.serviceName = StepZeroGate.servicePrefix
        #expect(StepZeroGate.decide(prefixed) == .run)
    }

    @Test func anUnreadFactRefuses() {
        var marker = ready()
        marker.marker = nil
        #expect(StepZeroGate.decide(marker) == .refused(.markerUnreadable))

        var expiry = ready()
        expiry.expiry = nil
        #expect(StepZeroGate.decide(expiry) == .refused(.expiryUnreadable))

        var overflow = ready()
        overflow.expiry = Int64.max
        overflow.now = Int64.min
        #expect(StepZeroGate.decide(overflow) == .refused(.expiryUnreadable))

        var seal = ready()
        seal.seal = .unread
        #expect(StepZeroGate.decide(seal) == .refused(.sealUnreadable))

        var parent = ready()
        parent.parentPID = nil
        #expect(StepZeroGate.decide(parent) == .refused(.parentUnreadable))

        for name: String? in [nil, ""] {
            var facts = ready()
            facts.serviceName = name
            #expect(StepZeroGate.decide(facts) == .refused(.serviceNameUnreadable))
        }

        var negative = ready()
        negative.otherZeus = -1
        #expect(StepZeroGate.decide(negative) == .refused(.otherZeusUnreadable))

        var census = ready()
        census.otherZeus = nil
        #expect(StepZeroGate.decide(census) == .refused(.otherZeusUnreadable))

        var qa = ready()
        qa.qaStart = nil
        #expect(StepZeroGate.decide(qa) == .refused(.qaUnreadable))

        var console = ready()
        console.onConsole = nil
        #expect(StepZeroGate.decide(console) == .refused(.consoleUnreadable))

        var lock = ready()
        lock.unlocked = nil
        #expect(StepZeroGate.decide(lock) == .refused(.lockUnreadable))
    }

    @Test func allSevenGiveRun() {
        #expect(StepZeroGate.decide(ready()) == .run)
        var two = ready()
        two.otherZeus = 2
        #expect(StepZeroGate.decide(two) == .refused(.otherZeus))
    }
}
