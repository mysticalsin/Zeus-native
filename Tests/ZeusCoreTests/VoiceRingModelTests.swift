import Foundation
import Testing
@testable import ZeusCore

@Suite struct VoiceRingModelTests {
    private func extent(_ points: [VoiceRingPoint]) -> (minX: Double, maxX: Double) {
        (points.map(\.x).min() ?? 0, points.map(\.x).max() ?? 0)
    }

    @Test func orbStyleDefaultsToMascot() {
        #expect(VoiceOrbStyle.resolve(nil) == .mascot)
        #expect(VoiceOrbStyle.resolve("nonsense") == .mascot)
        #expect(VoiceOrbStyle.resolve("ring") == .ring)
        #expect(VoiceOrbStyle.resolve("mono") == .mono)
        #expect(VoiceOrbStyle.defaultsKey == "voice.orbStyle")
    }

    @Test func ribbonIsBoundedForEveryStateAndExtreme() {
        for state in VoiceRingState.allCases {
            for lean in [-1.0, 0, 1] {
                let input = VoiceRingInput(time: 3.7, level: 1, weights: .pure(state), lean: lean, bend: 1, bendAngle: 0.4)
                for sample in VoiceRingModel.ribbon(input, samples: 120) {
                    for p in [sample.center, sample.outer, sample.inner] {
                        #expect(abs(p.x) <= 1 && abs(p.y) <= 1)
                    }
                    #expect(hypot(sample.outer.x - sample.inner.x, sample.outer.y - sample.inner.y) > 0)
                }
            }
        }
    }

    @Test func ribbonIsClosed() {
        let input = VoiceRingInput(time: 1.3, level: 0.6, weights: .pure(.speaking), lean: 0.3)
        let a = VoiceRingModel.radius(at: 0, input: input)
        let b = VoiceRingModel.radius(at: 2 * .pi, input: input)
        #expect(abs(a - b) < 1e-9)
        let samples = VoiceRingModel.ribbon(input, samples: 96)
        // The step from the last sample back to the first is as small as any other step.
        func gap(_ i: Int, _ j: Int) -> Double {
            hypot(samples[i].center.x - samples[j].center.x, samples[i].center.y - samples[j].center.y)
        }
        let maxGap = (0..<95).map { gap($0, $0 + 1) }.max() ?? 0
        #expect(gap(95, 0) <= maxGap * 1.5)
    }

    @Test func monoLoopsAreClosedAndBounded() {
        let input = VoiceRingInput(time: 2, level: 1, weights: .pure(.speaking), lean: 1, bend: 1)
        for loop in 0..<2 {
            let points = VoiceRingModel.monoLoop(loop, samples: 96, input: input)
            #expect(points.count == 96)
            #expect(points.allSatisfy { abs($0.x) <= 1 && abs($0.y) <= 1 })
        }
    }

    @Test func stateTransitionsAreContinuous() {
        var weights = VoiceRingWeights.pure(.idle)
        var previous = VoiceRingModel.ribbon(VoiceRingInput(time: 1, level: 0.5, weights: weights.eased), samples: 64)
        var frames = 0
        while weights != .pure(.speaking), frames < 200 {
            weights.advance(toward: .speaking, dt: 1.0 / 30, duration: 0.5)
            let next = VoiceRingModel.ribbon(VoiceRingInput(time: 1, level: 0.5, weights: weights.eased), samples: 64)
            for (a, b) in zip(previous, next) {
                #expect(hypot(a.outer.x - b.outer.x, a.outer.y - b.outer.y) < 0.05)
            }
            #expect(abs(weights.idle + weights.listening + weights.speaking + weights.processing - 1) < 1e-9)
            previous = next
            frames += 1
        }
        #expect(weights == .pure(.speaking))
        #expect(frames >= 14 && frames <= 16)
    }

    @Test func retargetingMidTransitionDoesNotJump() {
        var weights = VoiceRingWeights.pure(.idle)
        for _ in 0..<7 { weights.advance(toward: .listening, dt: 1.0 / 30, duration: 0.5) }
        let before = weights
        weights.advance(toward: .processing, dt: 1.0 / 30, duration: 0.5)
        #expect(abs(weights.listening - before.listening) < 0.1)
        #expect(abs(weights.idle - before.idle) < 0.1)
    }

    @Test func leanDirectionSign() {
        let right = extent(VoiceRingModel.ribbon(VoiceRingInput(weights: .pure(.idle), lean: 0.8), samples: 128).map(\.outer))
        let left = extent(VoiceRingModel.ribbon(VoiceRingInput(weights: .pure(.idle), lean: -0.8), samples: 128).map(\.outer))
        #expect(right.maxX > -right.minX)
        #expect(left.maxX < -left.minX)
        #expect(VoiceRingModel.center(VoiceRingInput(lean: 1)).x > 0)
        #expect(VoiceRingModel.center(VoiceRingInput(lean: -1)).x < 0)
    }

    @Test func hoverBendOnlyInIdleAndProcessing() {
        func rim(_ state: VoiceRingState, bend: Double) -> Double {
            let input = VoiceRingInput(time: 0.5, level: 0.4, weights: .pure(state), bend: bend, bendAngle: 0)
            return VoiceRingModel.radius(at: 0, input: input)
        }
        for state in [VoiceRingState.idle, .processing] {
            #expect(rim(state, bend: 1) > rim(state, bend: 0) + 0.01)
        }
        for state in [VoiceRingState.listening, .speaking] {
            #expect(rim(state, bend: 1) == rim(state, bend: 0))
        }
        // Away from the pointer the rim barely moves.
        let far = VoiceRingInput(weights: .pure(.idle), bend: 1, bendAngle: 0)
        let none = VoiceRingInput(weights: .pure(.idle))
        #expect(abs(VoiceRingModel.radius(at: .pi, input: far) - VoiceRingModel.radius(at: .pi, input: none)) < 0.002)
    }

    @Test func hoverAmountPeaksOnTheRim() {
        let onRim = VoiceRingModel.hover(x: VoiceRingModel.hoverRim, y: 0)
        let centre = VoiceRingModel.hover(x: 0, y: 0)
        let far = VoiceRingModel.hover(x: 1.4, y: 0)
        #expect(onRim.amount > 0.99 && abs(onRim.angle) < 1e-9)
        #expect(centre.amount == 0 && far.amount == 0)
        #expect(abs(VoiceRingModel.hover(x: 0, y: 0.6).angle - .pi / 2) < 1e-9)
    }

    @Test func reduceMotionIsStatic() {
        var early = VoiceRingEngine()
        var late = VoiceRingEngine()
        early.advance(dt: 0.05, state: .speaking, rawLevel: 0.2, reduceMotion: true)
        for _ in 0..<120 {
            late.advance(dt: 0.05, state: .speaking, rawLevel: Double.random(in: 0...1), hover: VoiceRingHover(amount: 1, angle: 1), reduceMotion: true)
        }
        let a = VoiceRingModel.ribbon(early.input(reduceMotion: true))
        let b = VoiceRingModel.ribbon(late.input(reduceMotion: true))
        #expect(a == b)
        #expect(late.time == 0 && late.level == 0 && late.bend == 0)
        #expect(late.weights == .pure(.speaking))
    }

    @Test func levelScalesWithSensitivityAndSmooths() {
        #expect(abs(VoiceRingModel.shapedLevel(raw: 0.5, sensitivity: 0.85) - 0.5) < 1e-9)
        #expect(VoiceRingModel.shapedLevel(raw: 0.5, sensitivity: 0) == 0)
        #expect(VoiceRingModel.shapedLevel(raw: 0.9, sensitivity: 2) == 1)
        let rise = VoiceRingModel.smoothLevel(previous: 0, target: 1, dt: 1.0 / 30)
        let fall = 1 - VoiceRingModel.smoothLevel(previous: 1, target: 0, dt: 1.0 / 30)
        #expect(rise > 0 && rise < 1)
        #expect(rise > fall)
        #expect(VoiceRingModel.smoothLevel(previous: 0.3, target: 0.3, dt: 0.5) == 0.3)
    }

    @Test func engineLevelOnlyInListeningAndSpeaking() {
        var engine = VoiceRingEngine()
        for _ in 0..<60 { engine.advance(dt: 1.0 / 30, state: .idle, rawLevel: 1) }
        #expect(engine.level == 0)
        for _ in 0..<60 { engine.advance(dt: 1.0 / 30, state: .listening, rawLevel: 1) }
        #expect(engine.level > 0.9)
    }

    @Test func emotionPalettes() {
        let none = VoiceRingModel.spectrum(nil)
        #expect(none.count == 4)
        for emotion in VoiceRingEmotion.allCases {
            let stops = VoiceRingModel.spectrum(emotion)
            #expect(stops.count == 4 && stops != none)
        }
        let start = VoiceRingModel.stops(from: nil, to: .calm, mix: 0)
        let end = VoiceRingModel.stops(from: nil, to: .calm, mix: 1)
        func close(_ a: [VoiceRingRGB], _ b: [VoiceRingRGB]) -> Bool {
            zip(a, b).allSatisfy { abs($0.r - $1.r) < 1e-9 && abs($0.g - $1.g) < 1e-9 && abs($0.b - $1.b) < 1e-9 }
        }
        #expect(close(start, none.map(VoiceRingModel.rgb)))
        #expect(close(end, VoiceRingModel.spectrum(.calm).map(VoiceRingModel.rgb)))
    }

    @Test func emotionFadesOverTime() {
        var engine = VoiceRingEngine(snappedTo: .idle)
        engine.advance(dt: 0.1, state: .idle, rawLevel: 0, emotion: .positive)
        #expect(engine.emotionMix < 1)
        for _ in 0..<30 { engine.advance(dt: 0.1, state: .idle, rawLevel: 0, emotion: .positive) }
        #expect(engine.emotionMix == 1)
    }

    @Test func proceduralLevelIsBounded() {
        for step in 0..<400 {
            let t = Double(step) * 0.05
            for state in VoiceRingState.allCases {
                let value = VoiceRingModel.proceduralLevel(time: t, state: state)
                #expect(value >= 0 && value <= 1)
            }
        }
        #expect(VoiceRingModel.proceduralLevel(time: 1, state: .idle) == 0)
    }
}
