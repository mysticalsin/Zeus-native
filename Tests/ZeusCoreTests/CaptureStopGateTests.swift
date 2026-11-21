import Foundation
import Testing
@testable import ZeusCore

@Suite struct CaptureStopGateTests {
    @Test func startWaitsUntilStopFinishes() {
        var gate = CaptureStopGate()
        #expect(gate.start())
        gate.requestStop()
        #expect(gate.start() == false)
        #expect(gate.running == false)
        gate.stopFinished()
        let started = gate.start()
        #expect(started)
        #expect(gate.running)
    }

    @Test func randomStopsNeverOverlapAStart() {
        var rng = StopSplitMix(state: 0x5709)
        for _ in 0..<250 {
            var gate = CaptureStopGate()
            for _ in 0..<Int(rng.next() % 10) + 1 {
                switch rng.next() % 3 {
                case 0:
                    let started = gate.start()
                    #expect(started == !gate.stopOpen || gate.running)
                    if gate.stopOpen { #expect(started == false) }
                case 1:
                    gate.requestStop()
                    #expect(gate.running == false)
                default:
                    gate.stopFinished()
                    #expect(gate.stopOpen == false)
                }
                #expect(!(gate.running && gate.stopOpen))
            }
        }
    }

    @Test func stressStopThenStartStaysSingleFile() {
        var gate = CaptureStopGate()
        for _ in 0..<400 {
            _ = gate.start()
            gate.requestStop()
            #expect(gate.start() == false)
            gate.stopFinished()
            let started = gate.start()
            #expect(started)
            gate.requestStop()
            gate.stopFinished()
        }
        #expect(gate.running == false)
        #expect(gate.stopOpen == false)
    }
}

struct StopSplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
