import Foundation
import Testing
@testable import ZeusCore

struct VoiceGlowModelTests {
    private let plain = VoiceGlowInput(sensitivity: 1, threshold: 0.2, attack: 0.05, release: 0.28)

    @Test func gateSilencesQuietInputAndRescalesTheRest() {
        #expect(plain.gated(0) == 0)
        #expect(plain.gated(0.2) == 0)
        #expect(plain.gated(0.1) == 0)
        #expect(abs(plain.gated(0.6) - 0.5) < 1e-9)
        #expect(plain.gated(1) == 1)
        #expect(plain.gated(.nan) == 0)
        #expect(plain.gated(-3) == 0)
    }

    @Test func sensitivityActsAsGainBeforeTheGate() {
        let loud = VoiceGlowInput(sensitivity: 2, threshold: 0.2, attack: 0.05, release: 0.28)
        #expect(loud.gated(0.3) > plain.gated(0.3))
        #expect(loud.gated(0.6) == 1)
    }

    @Test func attackRisesFasterThanReleaseFalls() {
        var up = VoiceGlowEnvelope(input: plain)
        up.step(level: 1, dt: 0.05)
        var down = VoiceGlowEnvelope(input: plain)
        for _ in 0..<100 { down.step(level: 1, dt: 0.05) }
        let top = down.value
        down.step(level: 0, dt: 0.05)
        #expect(up.value > 0.5)
        #expect(up.value > top - down.value)
        #expect(down.value > 0.7)
    }

    @Test func envelopeSettlesOnTheGatedTarget() {
        var envelope = VoiceGlowEnvelope(input: plain)
        for _ in 0..<400 { envelope.step(level: 0.6, dt: 1.0 / 30) }
        #expect(abs(envelope.value - 0.5) < 1e-3)
        for _ in 0..<400 { envelope.step(level: 0, dt: 1.0 / 30) }
        #expect(envelope.value < 1e-3)
    }

    @Test func envelopeIgnoresBadTimeSteps() {
        var envelope = VoiceGlowEnvelope(input: plain)
        envelope.step(level: 1, dt: 0.05)
        let held = envelope.value
        envelope.step(level: 0, dt: 0)
        envelope.step(level: 0, dt: -1)
        envelope.step(level: 0, dt: .nan)
        #expect(envelope.value == held)
    }

    @Test func presetGeometryIsSane() {
        for geometry in [VoiceGlowGeometry.default, .pill, .mobile] {
            #expect(geometry.reach > 0)
            #expect((0...1).contains(geometry.spread))
            #expect((0...1).contains(geometry.bend))
            #expect((0...1).contains(geometry.idle))
            #expect((1...VoiceGlowVariant.maxColors).contains(geometry.lobeCount))
            #expect(geometry.beamWidth > 0 && geometry.beamWidth < 1)
        }
        #expect(VoiceGlowGeometry.pill.reach <= 24)
        #expect(VoiceGlowGeometry.pill.reach < VoiceGlowGeometry.mobile.reach)
        #expect(VoiceGlowGeometry.mobile.reach < VoiceGlowGeometry.default.reach)
    }

    @Test func beamPositionStaysInBoundsAndSweeps() {
        for geometry in [VoiceGlowGeometry.default, .pill, .mobile] {
            let half = geometry.beamWidth / 2
            var low = 1.0, high = 0.0
            var clock = 0.0
            while clock < 20 {
                let position = VoiceGlowModel.beamPosition(clock: clock, period: geometry.beamPeriod, halfWidth: half)
                #expect(position >= half - 1e-9 && position <= 1 - half + 1e-9)
                low = min(low, position)
                high = max(high, position)
                clock += 0.05
            }
            #expect(low < 0.5 - 0.2 && high > 0.5 + 0.2)
            #expect(abs(VoiceGlowModel.beamPosition(clock: 0, period: geometry.beamPeriod, halfWidth: half) - 0.5) < 1e-9)
        }
        #expect(VoiceGlowModel.beamPosition(clock: .nan, period: 2, halfWidth: 0.1) == 0.5)
        #expect(VoiceGlowModel.beamPosition(clock: 1, period: 0, halfWidth: 0.1) == 0.5)
    }

    @Test func processingGathersLobesIntoANarrowBeam() {
        var model = VoiceGlowModel(geometry: .pill)
        let voiceSpan = Self.span(model.lobes(paletteCount: 7))
        for _ in 0..<90 { model.step(level: 0, processing: true, dt: 1.0 / 30) }
        #expect(model.gather > 0.99)
        let beamSpan = Self.span(model.lobes(paletteCount: 7))
        #expect(beamSpan < voiceSpan / 2)
        for lobe in model.lobes(paletteCount: 7) {
            #expect((0...1).contains(lobe.center) && (0...1).contains(lobe.height) && (0...0.5).contains(lobe.halfWidth))
        }
        for _ in 0..<150 { model.step(level: 0, processing: false, dt: 1.0 / 30) }
        #expect(model.gather == 0)
        #expect(model.beamClock == 0)
    }

    @Test func voiceRaisesTheGlowAboveIdle() {
        var model = VoiceGlowModel(geometry: .default)
        let resting = model.lobes(paletteCount: 7).map(\.height).max() ?? 0
        for _ in 0..<30 { model.step(level: 0.8, processing: false, dt: 1.0 / 30) }
        let speaking = model.lobes(paletteCount: 7).map(\.height).max() ?? 0
        #expect(speaking > resting)
        #expect(abs(resting - model.geometry.idle) < 0.05)
    }

    @Test func reduceMotionIsStaticWithNoBeamTravel() {
        var model = VoiceGlowModel(geometry: .pill)
        model.step(level: 1, processing: true, dt: 0.033, reduceMotion: true)
        let first = model.lobes(paletteCount: 7)
        for _ in 0..<60 { model.step(level: Double.random(in: 0...1), processing: true, dt: 0.033, reduceMotion: true) }
        #expect(model.lobes(paletteCount: 7) == first)
        #expect(model.gather == 0 && model.beamClock == 0)
        #expect(abs(model.drive - VoiceGlowGeometry.pill.reducedMotionLevel) < 1e-9)
        #expect(model.drive <= 0.35)
    }

    @Test func everyVariantHasOneToSevenColours() {
        #expect(VoiceGlowVariant.allCases.count == 8)
        for variant in VoiceGlowVariant.allCases {
            #expect((1...VoiceGlowVariant.maxColors).contains(variant.palette.count))
            #expect(!variant.title.isEmpty)
            for colour in variant.palette {
                #expect((0...1).contains(colour.red) && (0...1).contains(colour.green) && (0...1).contains(colour.blue))
            }
        }
        #expect(VoiceGlowVariant.colorful.palette.count == 7)
        #expect(Set(VoiceGlowVariant.allCases.map(\.rawValue)).count == 8)
    }

    @Test func variantResolveAndCustomColours() {
        #expect(VoiceGlowVariant.resolve(nil) == .colorful)
        #expect(VoiceGlowVariant.resolve("nonsense") == .colorful)
        #expect(VoiceGlowVariant.resolve("sunset") == .sunset)
        let many = (0..<10).map { VoiceGlowRGB(red: Double($0) / 10, green: 0, blue: 0) }
        #expect(VoiceGlowVariant.colors(variant: .ice, custom: many).count == 7)
        #expect(VoiceGlowVariant.colors(variant: .ice, custom: []) == VoiceGlowVariant.ice.palette)
    }

    @Test func strengthIsClamped() {
        #expect(VoiceGlowModel.clampStrength(-1) == 0)
        #expect(VoiceGlowModel.clampStrength(0.4) == 0.4)
        #expect(VoiceGlowModel.clampStrength(9) == 1)
        #expect(VoiceGlowModel.clampStrength(.nan) == 1)
    }

    private static func span(_ lobes: [VoiceGlowLobe]) -> Double {
        let centers = lobes.map(\.center)
        return (centers.max() ?? 0) - (centers.min() ?? 0)
    }
}
