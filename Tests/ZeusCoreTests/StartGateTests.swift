import Foundation
import Testing
@testable import ZeusCore

@Suite struct StartGateTests {
    @Test func theSecondStartIsRefused() {
        var gate = StartGate()
        let first = gate.start()
        let second = gate.start()
        #expect(first)
        #expect(second == false)
        #expect(gate.started)
    }

    @Test func randomStartsInstallOnce() {
        var rng = StartSplitMix(state: 0x57A7)
        for _ in 0..<200 {
            var gate = StartGate()
            var opened = false
            for _ in 0..<Int(rng.next() % 8) + 1 {
                let allowed = gate.start()
                #expect(allowed == !opened)
                opened = true
            }
            #expect(gate.started)
        }
    }

    @Test func stressAHundredStartsIsOneInstall() {
        var gate = StartGate()
        var installs = 0
        for _ in 0..<100 {
            if gate.start() { installs += 1 }
        }
        #expect(installs == 1)
        #expect(gate.started)
    }
}

struct StartSplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
