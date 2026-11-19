import AVFoundation
import Foundation
import Testing
@testable import Zeus

/// Generated PCM only: no AVAudioEngine, recognizer, capture device, controller or playback.
@Suite("Owned PCM conversion")
struct AudioSamplesConversionTests {
    private func buffer(_ samples: [Float], rate: Double) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: rate, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channel = try #require(buffer.floatChannelData?[0])
        for (index, value) in samples.enumerated() { channel[index] = value }
        return buffer
    }

    private final class Replies: @unchecked Sendable {
        private let lock = NSLock()
        private var supplied = 0
        private var exhausted = 0
        private var invalid = 0
        private var rejectedChecked = false
        private var droppedLive = false
        func record(status: AVAudioConverterInputStatus, buffer: AVAudioBuffer?, final: Bool) {
            let hasData = status == .haveData && (buffer as? AVAudioPCMBuffer)?.floatChannelData?[0][0] == 0.25
            let ended = buffer == nil && status == (final ? .endOfStream : .noDataNow)
            lock.withLock {
                if hasData { supplied += 1 }
                else if ended { exhausted += 1 }
                else { invalid += 1 }
            }
        }
        func record(checked: Bool, live: Bool) {
            lock.withLock { rejectedChecked = checked; droppedLive = live }
        }
        var counts: (Int, Int, Int) { lock.withLock { (supplied, exhausted, invalid) } }
        var contention: (Bool, Bool) { lock.withLock { (rejectedChecked, droppedLive) } }
    }

    @Test func inputOwnerSuppliesExactlyOnceAcrossConcurrentRequests() throws {
        for final in [false, true] {
            let input = PCMConversionInput(buffer: try buffer([0.25], rate: 48_000), final: final)
            let replies = Replies()
            DispatchQueue.concurrentPerform(iterations: 64) { _ in
                var status = AVAudioConverterInputStatus.noDataNow
                let supplied = input.take(status: &status)
                replies.record(status: status, buffer: supplied, final: final)
            }
            let (supplied, exhausted, invalid) = replies.counts
            #expect(supplied == 1 && exhausted == 63 && invalid == 0)
        }
    }

    @Test func sequentialBuffersPreserveWholeStreamAndFinalTail() throws {
        for rate in [48_000.0, 44_100.0] {
            let values = (0..<Int(rate / 10)).map { Float(sin(2 * Double.pi * 440 * Double($0) / rate) * 0.4) }
            let whole = try buffer(values, rate: rate)
            let expected = try AudioSamples.Resampler(from: whole.format).convertChecked(whole, final: true)
            // A tenth of a second at 16 kHz, including the converter's final tail.
            #expect(abs(expected.count - 1_600) <= 2)
            let reusable = try buffer(Array(repeating: 0, count: 1_024), rate: rate)
            let resampler = AudioSamples.Resampler(from: reusable.format)
            let channel = try #require(reusable.floatChannelData?[0])
            var converted: [Float] = []
            var offset = 0
            let sizes = [17, 511, 1_024, 63, 997]
            var iteration = 0
            while offset < values.count {
                let count = min(sizes[iteration % sizes.count], values.count - offset)
                reusable.frameLength = AVAudioFrameCount(count)
                for index in 0..<count { channel[index] = values[offset + index] }
                offset += count
                converted += try resampler.convertChecked(reusable, final: offset == values.count)
                // The returned samples must not borrow storage that the next input overwrites.
                for index in 0..<count { channel[index] = -0.75 }
                iteration += 1
            }
            #expect(converted.count == expected.count)
            #expect(zip(converted, expected).allSatisfy { abs($0.0 - $0.1) < 0.0001 })
        }
    }

    @Test func contestedConversionRejectsWithoutWaitingAndThenRecovers() throws {
        let source = try buffer(Array(repeating: 0.25, count: 4_800), rate: 48_000)
        let input = PCMConversionInput(buffer: source, final: true)
        let held = NSLock()
        let resampler = AudioSamples.Resampler(from: source.format, conversionLock: held)
        let replies = Replies()
        let started = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        held.lock()
        DispatchQueue.global().async {
            defer { done.signal() }
            var status = AVAudioConverterInputStatus.noDataNow
            guard let buffer = input.take(status: &status) as? AVAudioPCMBuffer else { return }
            started.signal()
            let rejected: Bool
            do { _ = try resampler.convertChecked(buffer); rejected = false }
            catch { rejected = error is AudioSamples.LoadError }
            replies.record(checked: rejected, live: resampler.convert(buffer).isEmpty)
        }
        let didStart = started.wait(timeout: .now() + 2) == .success
        let returnedWhileHeld = didStart && done.wait(timeout: .now() + 1) == .success
        held.unlock() // Release even on failure so a blocking regression can finish and be joined.
        let joined = returnedWhileHeld || done.wait(timeout: .now() + 2) == .success
        try #require(joined)
        #expect(didStart)
        #expect(returnedWhileHeld)
        let (checked, live) = replies.contention
        #expect(checked && live)
        let recovered = try resampler.convertChecked(source, final: true)
        #expect(!recovered.isEmpty && recovered.allSatisfy(\.isFinite))
    }
}
