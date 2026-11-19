import AudioToolbox
import CoreAudio
import Foundation
import Testing
import ZeusCore
@testable import Zeus

// The render block run on synthetic buffer lists: no device, no tap, no queue. It checks where each channel goes, that
// the counters add up, and that a callback longer than the scratch is carried out in chunks.

private struct Spec {
    var channels: Int
    var frames: Int
    var enabled = true
}

private func makeList(_ specs: [Spec]) -> UnsafeMutableAudioBufferListPointer {
    let list = AudioBufferList.allocate(maximumBuffers: specs.count)
    for (index, spec) in specs.enumerated() {
        if spec.enabled {
            let count = spec.channels * spec.frames
            let data = UnsafeMutablePointer<Float>.allocate(capacity: max(count, 1))
            data.initialize(repeating: 0, count: max(count, 1))
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(spec.channels), mDataByteSize: UInt32(count * MemoryLayout<Float>.size), mData: data)
        } else {
            list[index] = AudioBuffer(mNumberChannels: UInt32(spec.channels), mDataByteSize: 0, mData: nil)
        }
    }
    return list
}

private func release(_ list: UnsafeMutableAudioBufferListPointer) {
    for buffer in list { buffer.mData?.deallocate() }
    free(list.unsafeMutablePointer)
}

private func samples(_ list: UnsafeMutableAudioBufferListPointer, _ index: Int) -> UnsafeMutablePointer<Float> {
    list[index].mData!.assumingMemoryBound(to: Float.self)
}

private struct Run {
    let meter: ShapingMeterReading
}

private func render(
    input: UnsafeMutableAudioBufferListPointer,
    output: UnsafeMutableAudioBufferListPointer,
    map: [EqualiserChannelSource],
    tapIndex: Int = 0,
    maxFrames: Int = 512
) -> Run {
    let kernel = EqualiserKernel(maxChannels: 2, maxFrames: maxFrames, bandCount: EqualiserParameters.bandCount)
    kernel.mailbox.post(.flat)
    let meter = TapMeter()
    let block = AppShapingTap.makeRenderBlock(
        kernel: kernel, scratch: RenderScratch(maxChannels: 2, maxFrames: maxFrames),
        map: RenderChannelMap(map), tapIndex: tapIndex, meter: meter, sampleRate: 48_000)
    var stamp = AudioTimeStamp()
    withUnsafePointer(to: &stamp) { time in
        block(time, input.unsafePointer, time, output.unsafeMutablePointer, time)
    }
    return Run(meter: meter.reading)
}

private func fillStereo(_ list: UnsafeMutableAudioBufferListPointer, _ index: Int, frames: Int) {
    let data = samples(list, index)
    for frame in 0..<frames {
        data[frame * 2] = 0.25 * Float(sin(Double(frame) * 0.1))
        data[frame * 2 + 1] = 0.125 * Float(cos(Double(frame) * 0.07))
    }
}

@Suite("Shaping render block")
struct AppShapingRenderTests {
    @Test func stereoInterleavedGoesToAStereoDeviceUnchangedWhenFlat() {
        let input = makeList([Spec(channels: 2, frames: 100)])
        let output = makeList([Spec(channels: 2, frames: 100)])
        defer { release(input); release(output) }
        fillStereo(input, 0, frames: 100)
        let run = render(input: input, output: output, map: [.tap(0), .tap(1)])
        for index in 0..<200 {
            #expect(abs(samples(output, 0)[index] - samples(input, 0)[index]) < 1e-6)
        }
        #expect(run.meter.callbacks == 1)
        #expect(run.meter.frames == 100)
        #expect(run.meter.zeroFrames == 0)
    }

    @Test func aStereoPairOnALargerDeviceLeavesTheOtherChannelsSilent() {
        let input = makeList([Spec(channels: 2, frames: 64)])
        let output = makeList([Spec(channels: 4, frames: 64)])
        defer { release(input); release(output) }
        fillStereo(input, 0, frames: 64)
        _ = render(input: input, output: output, map: [.silence, .silence, .tap(0), .tap(1)])
        for frame in 0..<64 {
            #expect(samples(output, 0)[frame * 4] == 0)
            #expect(samples(output, 0)[frame * 4 + 1] == 0)
            #expect(abs(samples(output, 0)[frame * 4 + 2] - samples(input, 0)[frame * 2]) < 1e-6)
            #expect(abs(samples(output, 0)[frame * 4 + 3] - samples(input, 0)[frame * 2 + 1]) < 1e-6)
        }
    }

    @Test func aMonoDeviceGetsTheAverage() {
        let input = makeList([Spec(channels: 2, frames: 64)])
        let output = makeList([Spec(channels: 1, frames: 64)])
        defer { release(input); release(output) }
        fillStereo(input, 0, frames: 64)
        _ = render(input: input, output: output, map: [.average])
        for frame in 0..<64 {
            let mean = (samples(input, 0)[frame * 2] + samples(input, 0)[frame * 2 + 1]) / 2
            #expect(abs(samples(output, 0)[frame] - mean) < 1e-6)
        }
    }

    @Test func aDeviceWithOneBufferPerChannelIsFilledChannelByChannel() {
        let input = makeList([Spec(channels: 2, frames: 32)])
        let output = makeList([Spec(channels: 1, frames: 32), Spec(channels: 1, frames: 32)])
        defer { release(input); release(output) }
        fillStereo(input, 0, frames: 32)
        _ = render(input: input, output: output, map: [.tap(0), .tap(1)])
        for frame in 0..<32 {
            #expect(abs(samples(output, 0)[frame] - samples(input, 0)[frame * 2]) < 1e-6)
            #expect(abs(samples(output, 1)[frame] - samples(input, 0)[frame * 2 + 1]) < 1e-6)
        }
    }

    @Test func exactZerosAreCountedAndStaySilent() {
        let input = makeList([Spec(channels: 2, frames: 128)])
        let output = makeList([Spec(channels: 2, frames: 128)])
        defer { release(input); release(output) }
        let run = render(input: input, output: output, map: [.tap(0), .tap(1)])
        #expect(run.meter.frames == 128)
        #expect(run.meter.zeroFrames == 128)
        #expect((0..<256).allSatisfy { samples(output, 0)[$0] == 0 })
    }

    @Test func aCallbackLongerThanTheScratchRunsInChunks() {
        let input = makeList([Spec(channels: 2, frames: 200)])
        let output = makeList([Spec(channels: 2, frames: 200)])
        defer { release(input); release(output) }
        fillStereo(input, 0, frames: 200)
        let run = render(input: input, output: output, map: [.tap(0), .tap(1)], maxFrames: 64)
        #expect(run.meter.frames == 200)
        for index in 0..<400 {
            #expect(abs(samples(output, 0)[index] - samples(input, 0)[index]) < 1e-6)
        }
    }

    @Test func onlyTheTapsBufferIsReadWhenOtherInputsAreOff() {
        let input = makeList([Spec(channels: 1, frames: 0, enabled: false), Spec(channels: 2, frames: 48)])
        let output = makeList([Spec(channels: 2, frames: 48)])
        defer { release(input); release(output) }
        fillStereo(input, 1, frames: 48)
        let run = render(input: input, output: output, map: [.tap(0), .tap(1)], tapIndex: 1)
        #expect(run.meter.frames == 48)
        #expect(abs(samples(output, 0)[10] - samples(input, 1)[10]) < 1e-6)
    }

    @Test func aMissingTapBufferWritesSilenceAndStillCountsTheCallback() {
        let input = makeList([Spec(channels: 1, frames: 0, enabled: false)])
        let output = makeList([Spec(channels: 2, frames: 16)])
        defer { release(input); release(output) }
        for index in 0..<32 { samples(output, 0)[index] = 0.5 }
        let run = render(input: input, output: output, map: [.tap(0), .tap(1)])
        #expect(run.meter.callbacks == 1)
        #expect(run.meter.frames == 0)
        #expect((0..<32).allSatisfy { samples(output, 0)[$0] == 0 })
    }

    @Test func theProbeBlockCountsAndWritesNothing() {
        let input = makeList([Spec(channels: 2, frames: 64)])
        defer { release(input) }
        fillStereo(input, 0, frames: 64)
        let meter = TapMeter()
        let block = AppShapingTap.makeProbeBlock(meter: meter, tapIndex: 0)
        var stamp = AudioTimeStamp()
        let output = makeList([Spec(channels: 2, frames: 64)])
        defer { release(output) }
        for index in 0..<128 { samples(output, 0)[index] = 0.5 }
        withUnsafePointer(to: &stamp) { time in
            block(time, input.unsafePointer, time, output.unsafeMutablePointer, time)
        }
        #expect(meter.reading.callbacks == 1)
        #expect(meter.reading.frames == 64)
        #expect((0..<128).allSatisfy { samples(output, 0)[$0] == 0.5 })
    }

    @Test func aBoostedBandRaisesTheShapedLevelAndNeverClips() {
        let frames = 4_800
        let input = makeList([Spec(channels: 2, frames: frames)])
        let output = makeList([Spec(channels: 2, frames: frames)])
        defer { release(input); release(output) }
        for frame in 0..<frames {
            let value = Float(sin(2 * Double.pi * 100 * Double(frame) / 48_000))
            samples(input, 0)[frame * 2] = value
            samples(input, 0)[frame * 2 + 1] = value
        }
        let kernel = EqualiserKernel(maxChannels: 2, maxFrames: 512, bandCount: EqualiserParameters.bandCount)
        kernel.mailbox.post(EqualiserParameters(gainsDB: [12, 12, 12, 12, 12, 12, 12, 12, 12, 12], volume: 1, bypass: false))
        let block = AppShapingTap.makeRenderBlock(
            kernel: kernel, scratch: RenderScratch(maxChannels: 2, maxFrames: 512),
            map: RenderChannelMap([.tap(0), .tap(1)]), tapIndex: 0, meter: TapMeter(), sampleRate: 48_000)
        var stamp = AudioTimeStamp()
        withUnsafePointer(to: &stamp) { time in
            block(time, input.unsafePointer, time, output.unsafeMutablePointer, time)
        }
        let peak = (0..<(frames * 2)).map { abs(samples(output, 0)[$0]) }.max() ?? 0
        #expect(peak <= 1)
        #expect(peak > 0.1)
    }
}
