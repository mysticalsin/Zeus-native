import Foundation
import Testing
@testable import ZeusCore

@Suite("Spatial trail memory")
struct SpatialTrailMemoryTests {
    @Test func aShortRunKeepsEverySampleAndNoDwell() {
        var memory = SpatialTrailMemory()
        for step in 0..<10 {
            memory.add(x: 3, y: Double(step) * 0.2, at: Double(step) * 0.02)
        }
        #expect(memory.samples.count == 10)
        #expect(memory.droppedSamples == 0)
        #expect(memory.dwells.isEmpty)
        #expect(memory.samples.first == SpatialTrailSample(x: 3, y: 0, time: 0))
        #expect(memory.samples.last == SpatialTrailSample(x: 3, y: 1.8, time: 0.18))
    }

    @Test func theSampleCapDropsTheOldest() {
        var memory = SpatialTrailMemory()
        let cap = SpatialTrailMemory.maxSamples
        for step in 0..<cap {
            memory.add(x: Double(step) * 13, y: 0, at: Double(step))
        }
        #expect(memory.samples.count == cap)
        #expect(memory.droppedSamples == 0)
        #expect(memory.samples.first == SpatialTrailSample(x: 0, y: 0, time: 0))
        #expect(memory.dwells.isEmpty)
        memory.add(x: Double(cap) * 13, y: 0, at: Double(cap))
        #expect(memory.samples.count == cap)
        #expect(memory.droppedSamples == 1)
        #expect(memory.samples.first == SpatialTrailSample(x: 13, y: 0, time: 1))
        #expect(memory.samples.last == SpatialTrailSample(x: Double(cap) * 13, y: 0, time: Double(cap)))
    }

    @Test func aNonFiniteSampleIsDroppedAndDoesNotMoveTheRest() {
        var memory = SpatialTrailMemory()
        memory.add(x: 0, y: 0, at: 0)
        memory.add(x: .nan, y: 0, at: 0.1)
        memory.add(x: 0, y: .nan, at: 0.2)
        memory.add(x: 0, y: 0, at: .nan)
        memory.add(x: .infinity, y: 0, at: 0.3)
        memory.add(x: 0, y: -.infinity, at: 0.4)
        memory.add(x: 0, y: 0, at: SpatialTrailMemory.dwellQualification)
        #expect(memory.droppedSamples == 5)
        #expect(memory.samples == [
            SpatialTrailSample(x: 0, y: 0, time: 0),
            SpatialTrailSample(x: 0, y: 0, time: SpatialTrailMemory.dwellQualification),
        ])
        #expect(memory.dwells == [SpatialTrailSample(x: 0, y: 0, time: 0)])
    }

    @Test func aRestShorterThanTheQualificationRecordsNothing() {
        var memory = SpatialTrailMemory()
        memory.add(x: 0, y: 0, at: 0)
        memory.add(x: 0, y: 0, at: SpatialTrailMemory.dwellQualification - 0.001)
        #expect(memory.dwells.isEmpty)
        #expect(memory.samples.count == 2)
        #expect(memory.droppedSamples == 0)
    }

    @Test func aRestAtTheRadiusRecordsTheAnchorOnce() {
        var memory = SpatialTrailMemory()
        memory.add(x: 0, y: 0, at: 0)
        memory.add(x: SpatialTrailMemory.dwellRadius, y: 0, at: SpatialTrailMemory.dwellQualification)
        memory.add(x: SpatialTrailMemory.dwellRadius, y: 0, at: 2)
        #expect(memory.dwells == [SpatialTrailSample(x: 0, y: 0, time: 0)])
        #expect(memory.samples.count == 3)
    }

    @Test func leavingTheRadiusAllowsAnotherDwell() {
        var memory = SpatialTrailMemory()
        memory.add(x: 0, y: 0, at: 0)
        memory.add(x: 12.01, y: 0, at: 1)
        #expect(memory.dwells.isEmpty)
        memory.add(x: 12.01, y: 0, at: 1 + SpatialTrailMemory.dwellQualification)
        #expect(memory.dwells == [SpatialTrailSample(x: 12.01, y: 0, time: 1)])
    }

    @Test func dwellsStopAtSixteen() {
        var memory = SpatialTrailMemory()
        let limit = SpatialTrailMemory.maxDwells
        for index in 0..<limit {
            let x = Double(index) * 13
            let start = Double(index) * 2
            memory.add(x: x, y: 0, at: start)
            memory.add(x: x, y: 0, at: start + 1)
        }
        #expect(memory.dwells.count == limit)
        #expect(memory.dwells.first == SpatialTrailSample(x: 0, y: 0, time: 0))
        #expect(memory.dwells.last == SpatialTrailSample(x: Double(limit - 1) * 13, y: 0, time: Double(limit - 1) * 2))
        let extra = Double(limit) * 13
        let extraStart = Double(limit) * 2
        memory.add(x: extra, y: 0, at: extraStart)
        memory.add(x: extra, y: 0, at: extraStart + 1)
        #expect(memory.dwells.count == limit)
        #expect(memory.dwells.last?.x == Double(limit - 1) * 13)
    }

    @Test func aRecordedDwellStaysAfterItsSampleIsDropped() {
        var memory = SpatialTrailMemory()
        memory.add(x: 0, y: 0, at: 0)
        memory.add(x: 0, y: 0, at: SpatialTrailMemory.dwellQualification)
        let cap = SpatialTrailMemory.maxSamples
        for step in 0..<cap {
            memory.add(x: 100 + Double(step) * 13, y: 0, at: 10 + Double(step))
        }
        #expect(memory.dwells == [SpatialTrailSample(x: 0, y: 0, time: 0)])
        #expect(memory.samples.count == cap)
        #expect(memory.samples.contains { $0.x == 0 } == false)
        #expect(memory.droppedSamples == 2)
    }
}
