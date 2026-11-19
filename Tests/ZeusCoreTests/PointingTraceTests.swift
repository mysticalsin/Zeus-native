import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing trace")
struct PointingTraceTests {
    private func sample(_ t: Double, _ x: Double = 0, _ y: Double = 0) -> PointerSample {
        PointerSample(time: t, x: x, y: y, displayID: 1)
    }

    @Test func samplesAreCappedAndTheLossIsCounted() {
        var trace = PointingTrace()
        for index in 0..<(PointingTrace.maxSamples + 10) { trace.add(sample(Double(index), Double(index) * 20)) }
        #expect(trace.samples.count == PointingTrace.maxSamples)
        #expect(trace.droppedSamples == 10)
        #expect(trace.samples.first?.time == 10)
    }

    @Test func nonFiniteSamplesAreRejectedAndCounted() {
        var trace = PointingTrace()
        trace.add(sample(0, .nan, 0))
        #expect(trace.samples.isEmpty && trace.droppedSamples == 1)
    }

    @Test func restingInsideTwelvePointsForThreeHundredFiftyMillisecondsIsOneDwell() {
        var trace = PointingTrace()
        #expect(trace.add(sample(0, 100, 100)) == nil)
        #expect(trace.add(sample(0.2, 103, 101)) == nil)
        let dwell = trace.add(sample(0.4, 104, 100))
        #expect(dwell?.at.x == 100)
        #expect(trace.add(sample(0.8, 104, 100)) == nil) // Recorded once per rest.
        #expect(trace.dwells.count == 1)
        // Moving away and resting again is a second dwell.
        trace.add(sample(1.0, 400, 400))
        #expect(trace.add(sample(1.5, 401, 400)) != nil)
        #expect(trace.dwells.count == 2)
    }

    @Test func dwellCountIsBounded() {
        var trace = PointingTrace()
        for index in 0..<40 {
            let x = Double(index) * 100
            trace.add(sample(Double(index) * 2, x))
            trace.add(sample(Double(index) * 2 + 0.5, x))
        }
        #expect(trace.dwells.count == PointingTrace.maxDwells)
    }

    @Test func strokesCollectOnlyWhileOpenAndAreBounded() {
        var trace = PointingTrace()
        trace.add(sample(0, 1, 1))
        trace.beginStroke(id: "s0")
        trace.add(sample(1, 50, 50)); trace.add(sample(2, 80, 80))
        trace.endStroke()
        trace.add(sample(3, 300, 300))
        #expect(trace.strokes.count == 1)
        #expect(trace.strokes[0].samples.count == 2)
        for index in 0..<(PointingTrace.maxStrokes + 5) { trace.beginStroke(id: "x\(index)"); trace.endStroke() }
        #expect(trace.strokes.count == PointingTrace.maxStrokes)
    }

    @Test func sampleAtAudioOffsetFindsTheNearestInTime() {
        var trace = PointingTrace()
        for (index, t) in [10.0, 10.5, 11.0, 11.5].enumerated() { trace.add(sample(t, Double(index) * 100)) }
        #expect(trace.sample(atAudioOffset: 0.6, audioStart: 10)?.x == 100)
        #expect(trace.sample(atAudioOffset: 1.4, audioStart: 10)?.x == 300)
        #expect(PointingTrace().sample(atAudioOffset: 0, audioStart: 0) == nil)
        #expect(trace.sample(atAudioOffset: .nan, audioStart: 0) == nil)
    }

    @Test func downsamplingKeepsTheEndpoints() {
        var trace = PointingTrace()
        for index in 0..<1000 { trace.add(sample(Double(index), Double(index) * 20)) }
        let reduced = trace.downsampled(limit: 256)
        #expect(reduced.count == 256)
        #expect(reduced.first?.time == 0 && reduced.last?.time == 999)
    }
}
