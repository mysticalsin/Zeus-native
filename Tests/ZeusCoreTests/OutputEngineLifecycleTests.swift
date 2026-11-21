import Foundation
import Testing
@testable import ZeusCore

@Suite struct OutputEngineLifecycleTests {
    @Test func stopHaltsTheEngine() {
        var engine = OutputEngineLifecycle()
        engine.start()
        engine.stop()
        #expect(engine.running == false)
    }

    @Test func stopBeforeStartStaysStopped() {
        var engine = OutputEngineLifecycle()
        engine.stop()
        #expect(engine.running == false)
    }

    @Test func randomStartAndStopEndsStopped() {
        var rng = OutputSplitMix(state: 0xE0611E)
        for _ in 0..<300 {
            var engine = OutputEngineLifecycle()
            let steps = Int(rng.next() % 12) + 1
            var started = false
            for _ in 0..<steps {
                if rng.next() % 2 == 0 {
                    engine.start()
                    started = true
                    #expect(engine.running)
                } else {
                    engine.stop()
                    #expect(engine.running == false)
                    started = false
                }
            }
            if started {
                engine.stop()
                #expect(engine.running == false)
            }
        }
    }

    @Test func stressRestartNeverSurvivesStop() {
        var engine = OutputEngineLifecycle()
        for _ in 0..<400 {
            engine.start()
            engine.start()
            engine.stop()
            #expect(engine.running == false)
        }
    }
}

struct OutputSplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
