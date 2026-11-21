import Foundation
import Testing
@testable import ZeusCore

@Suite struct CameraRunTests {
    @Test func aSecondStartRebindsInterruptions() {
        var camera = CameraRun()
        let first = camera.start()
        let second = camera.start()
        #expect(second != first)
        let secondDelivers = camera.delivers(second)
        let firstDelivers = camera.delivers(first)
        #expect(secondDelivers)
        #expect(firstDelivers == false)
    }

    @Test func randomStartsDeliverOnlyTheLatestRun() {
        var rng = CameraSplitMix(state: 0xCA3E)
        for _ in 0..<200 {
            var camera = CameraRun()
            var latest = 0
            for _ in 0..<Int(rng.next() % 6) + 1 {
                latest = camera.start()
                #expect(camera.delivers(latest))
            }
            #expect(camera.delivers(latest))
            if latest > 1 {
                #expect(camera.delivers(latest - 1) == false)
            }
        }
    }

    @Test func stressFiftyStartsStayOnTheLastRun() {
        var camera = CameraRun()
        var last = 0
        for _ in 0..<50 { last = camera.start() }
        #expect(last == 50)
        #expect(camera.delivers(50))
        #expect(camera.delivers(49) == false)
    }
}

struct CameraSplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
