import Darwin
import Foundation
import Testing
@testable import ZeusCore

// Kept out of the portable equaliser group: this check runs only with ZEUS_ALLOC_CHECK=1 (malloc counts are not
// reliable while other suites run in parallel), and the portable gate treats a skipped test as a failure.

private func sine(_ frequency: Double, amplitude: Double, frames: Int, start: Int = 0, sampleRate: Double) -> [Float] {
    (0..<frames).map { Float(amplitude * sin(2 * Double.pi * frequency * Double(start + $0) / sampleRate)) }
}

private func parameters(_ gains: [Int: Double] = [:], volume: Double = 1, bypass: Bool = false) -> EqualiserParameters {
    var values = [Double](repeating: 0, count: EqualiserParameters.bandCount)
    for (band, gain) in gains { values[band] = gain }
    return EqualiserParameters(gainsDB: values, volume: volume, bypass: bypass)
}

// MARK: - 8. Allocation

@Suite(.serialized) struct EqualiserKernelAllocationTests {
    private static func blocksInUse() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Int(stats.blocks_in_use)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ZEUS_ALLOC_CHECK"] == "1"))
    func aThousandBuffersAllocateNothing() {
        let frames = 512
        let rate = 48000.0
        let kernel = EqualiserKernel(maxChannels: 2, maxFrames: frames, bandCount: 10)
        let loud = parameters(Dictionary(uniqueKeysWithValues: (0..<10).map { ($0, 9.0) }), volume: 0.7)
        let quiet = parameters([2: -5, 6: 4], volume: 1)
        var buffer = sine(300, amplitude: 1, frames: frames, sampleRate: rate)
        buffer += buffer
        buffer.withUnsafeMutableBufferPointer { pointer in
            let base = pointer.baseAddress!
            for _ in 0..<40 {
                kernel.process(base, frames: frames, channels: 2, interleaved: false, sampleRate: rate)
            }
            let before = Self.blocksInUse()
            for index in 0..<1000 {
                if index % 100 == 0 { kernel.mailbox.post(index % 200 == 0 ? loud : quiet) }
                if index == 500 { base[10] = .nan }
                kernel.process(base, frames: frames, channels: 2, interleaved: index % 2 == 0, sampleRate: rate)
            }
            let after = Self.blocksInUse()
            #expect(after == before)
        }
    }
}
