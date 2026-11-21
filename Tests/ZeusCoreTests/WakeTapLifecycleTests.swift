import Foundation
import Testing
@testable import ZeusCore

@Suite struct WakeTapLifecycleTests {
    @Test func aStoppedEngineStillLosesItsTap() {
        var tap = WakeTapLifecycle()
        tap.install()
        #expect(tap.remove() == .removed)
        #expect(tap.installed == false)
    }

    @Test func aSecondRemoveDoesNotTouchTheEngine() {
        var tap = WakeTapLifecycle()
        tap.install()
        #expect(tap.remove() == .removed)
        #expect(tap.remove() == .alreadyClear)
        #expect(tap.installed == false)
    }

    @Test func removeBeforeInstallIsClear() {
        var tap = WakeTapLifecycle()
        #expect(tap.remove() == .alreadyClear)
    }

    @Test func randomInstallAndRemoveNeverLeavesATapAfterRemove() {
        var tap = WakeTapLifecycle()
        var rng = SplitMix64(state: 0xA11CE)
        for _ in 0..<400 {
            if rng.next() % 3 == 0 {
                tap.install()
                #expect(tap.installed)
            } else {
                let result = tap.remove()
                #expect(tap.installed == false)
                if result == .removed {
                    #expect(tap.remove() == .alreadyClear)
                } else {
                    #expect(result == .alreadyClear)
                }
            }
        }
    }

    @Test func interleavedStopsStayIdempotent() {
        var rng = SplitMix64(state: 0x7A9E)
        for _ in 0..<200 {
            var tap = WakeTapLifecycle()
            let installs = Int(rng.next() % 5)
            for _ in 0..<installs { tap.install() }
            let stops = Int(rng.next() % 6)
            var removed = false
            for _ in 0..<stops {
                switch tap.remove() {
                case .removed:
                    #expect(removed == false)
                    removed = true
                case .alreadyClear:
                    #expect(installs == 0 || removed)
                case .leftInstalled:
                    Issue.record("a remove left the tap installed")
                }
            }
            #expect(tap.installed == false)
        }
    }
}

/// A fixed sequence so a stress loop fails the same way twice.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
