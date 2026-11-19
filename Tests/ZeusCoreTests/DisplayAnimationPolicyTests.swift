import Testing
@testable import ZeusCore

@Suite("Display-synchronized animation policy")
struct DisplayAnimationPolicyTests {
    @Test func requestedCadenceUsesTheActualDisplayAndSupports240Hz() {
        for rate in [60, 120, 144, 165, 240] {
            #expect(DisplayAnimationPolicy.requestedFramesPerSecond(screenMaximum: rate) == rate)
        }
        #expect(DisplayAnimationPolicy.requestedFramesPerSecond(screenMaximum: 360) == 240)
        #expect(DisplayAnimationPolicy.requestedFramesPerSecond(screenMaximum: 240, preferred: 60) == 60)
    }

    @Test func unknownDisplaysAndInvalidPreferencesNeverInventAFrameRate() {
        #expect(DisplayAnimationPolicy.requestedFramesPerSecond(screenMaximum: 0) == 0)
        #expect(DisplayAnimationPolicy.requestedFramesPerSecond(screenMaximum: -1) == 0)
        #expect(DisplayAnimationPolicy.requestedFramesPerSecond(screenMaximum: 240, preferred: 0) == 0)
        #expect(DisplayAnimationPolicy.requestedFramesPerSecond(screenMaximum: 240, preferred: -1) == 0)
        #expect(DisplayAnimationPolicy.requestedFramesPerSecond(screenMaximum: .max, preferred: .max) == 240)
    }

    @Test func everyHiddenPausedDetachedOrReducedStateBlocksPublication() {
        func permits(appeared: Bool = true, paused: Bool = false, reduced: Bool = false,
                     attached: Bool = true, hidden: Bool = false, visible: Bool = true,
                     miniaturized: Bool = false, alpha: Double = 1) -> Bool {
            DisplayAnimationPolicy.mayPublish(appeared: appeared, paused: paused, reduceMotion: reduced,
                attached: attached, hidden: hidden, windowVisible: visible, miniaturized: miniaturized, windowAlpha: alpha)
        }
        #expect(permits())
        #expect(!permits(appeared: false))
        #expect(!permits(paused: true))
        #expect(!permits(reduced: true))
        #expect(!permits(attached: false))
        #expect(!permits(hidden: true))
        #expect(!permits(visible: false))
        #expect(!permits(miniaturized: true))
        for alpha in [0.0, 0.01, -1, .nan, .infinity, -.infinity] { #expect(!permits(alpha: alpha)) }
    }

    @Test func callbackMetricsMeasureSyntheticCadenceWithoutClaimingRenderedFrames() {
        for frequency in [60.0, 120, 240] {
            var metrics = DisplayCallbackMetrics()
            #expect(metrics.measuredCallbackFrequency == nil)
            for frame in 0...Int(frequency) {
                let target = 100 + Double(frame) / frequency
                let accepted = metrics.record(target: target, delivered: target - 0.001)
                #expect(accepted)
            }
            #expect(metrics.callbackCount == UInt64(frequency) + 1)
            #expect(abs((metrics.measuredCallbackFrequency ?? 0) - frequency) < 1e-8)
            #expect(metrics.deliveredAfterTargetCount == 0)
            #expect(metrics.maximumCallbackWork == 0)
        }
    }

    @Test func duplicateBackwardAndInvalidTimestampsCannotCreatePublicationBacklog() {
        var metrics = DisplayCallbackMetrics()
        let first = metrics.record(target: 10, delivered: 9.999)
        #expect(first)
        let baseline = metrics
        for input: (Double, Double) in [(10, 10), (9, 10), (.nan, 10), (11, .infinity),
                                       (.infinity, 11), (-1, 11), (11, 9), (11, -1)] {
            let accepted = metrics.record(target: input.0, delivered: input.1)
            #expect(!accepted)
            #expect(metrics == baseline)
        }
        let next = metrics.record(target: 11, delivered: 10.999)
        #expect(next)
        #expect(metrics.callbackCount == 2)
    }

    @Test func lateDeliveryAndCallbackWorkRemainSeparateMeasurements() {
        var metrics = DisplayCallbackMetrics()
        let first = metrics.record(target: 1, delivered: 0.999)
        let second = metrics.record(target: 2, delivered: 2.0002)
        let third = metrics.record(target: 3, delivered: 3.003)
        #expect(first && second && third)
        #expect(metrics.deliveredAfterTargetCount == 2)
        #expect(abs(metrics.maximumLateness - 0.003) < 1e-10)
        metrics.recordCallbackWork(0.0004)
        metrics.recordCallbackWork(0.0002)
        metrics.recordCallbackWork(.nan)
        metrics.recordCallbackWork(-1)
        #expect(metrics.maximumCallbackWork == 0.0004)
        #expect(metrics.deliveredAfterTargetCount == 2)
    }

    @Test func wallClockCorrectionsKeepNewCompletionsInTheProducersTimeDomain() throws {
        // Monotonic callbacks stay near 100; the system clock can move in either direction.
        for wallNow in [10_000.0, 50_000, 5_000] {
            let presentation = try #require(DisplayAnimationPolicy.presentationTime(
                wallNow: wallNow, targetTimestamp: 100.004, deliveredAt: 100))
            let snapshot = RecordingFeedback.Snapshot(producer: .meetings, phase: .completed,
                sessionKey: "fixture", beganAt: wallNow - 1, label: "Saved")
            let frame = RecordingFeedback.frame(snapshot, at: presentation, reduceMotion: false, reduceTransparency: false)
            #expect(frame.visible && frame.reveal == 1)
            #expect(abs(presentation - wallNow - 0.004) < 1e-8)
        }
        #expect(DisplayAnimationPolicy.presentationTime(wallNow: 50, targetTimestamp: 200, deliveredAt: 100) == 50.1)
        #expect(DisplayAnimationPolicy.presentationTime(wallNow: 50, targetTimestamp: 99, deliveredAt: 100) == 50)
        #expect(DisplayAnimationPolicy.presentationTime(wallNow: .nan, targetTimestamp: 101, deliveredAt: 100) == nil)
    }

    @Test func finiteAnimationStopsOnceAtItsDeadlineAndRestartsOnlyForNewWork() {
        var deadline = DisplayAnimationDeadline()
        deadline.configure(until: 10, now: 9)
        #expect(!deadline.reached)
        let early = deadline.finishIfNeeded(at: 9.999)
        let final = deadline.finishIfNeeded(at: 10)
        let repeated = deadline.finishIfNeeded(at: 11)
        #expect(!early && final && !repeated && deadline.reached)
        // Predicting the final display a little ahead of wall time cannot undo the last frame.
        #expect(deadline.settledTime(now: 9.999, lastFrame: 10.004) == 10.004)
        #expect(deadline.settledTime(now: 12, lastFrame: 10.004) == 12)
        deadline.configure(until: 20, now: 12)
        #expect(!deadline.reached)
        deadline.configure(until: 11, now: 12)
        #expect(deadline.reached)
        deadline.configure(until: .nan, now: 12)
        #expect(deadline.reached)
        deadline.configure(until: nil, now: 12)
        let unbounded = deadline.finishIfNeeded(at: 1_000)
        #expect(!deadline.reached && !unbounded)
    }
}
