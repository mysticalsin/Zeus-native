import CoreFoundation
import Foundation
import Testing
@testable import ZeusCore

@Suite("Private-content-free explanation diagnostics")
struct ExplanationDiagnosticsTests {
    // Evaluate mutating value operations before entering Swift Testing macros.
    private func check(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(value, sourceLocation: sourceLocation)
    }
    private func require<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) throws -> T {
        try #require(value, sourceLocation: sourceLocation)
    }
    private final class Clock { var seconds: Double; init(_ seconds: Double = 0) { self.seconds = seconds } }

    @Test func firstActualEventsUseMonotonicLatencyAndNeverInferAudioOrPhotons() throws {
        let clock = Clock(10)
        var diagnostics = ExplanationDiagnostics(clock: { clock.seconds })
        let token = try require((diagnostics.beginTurn(identity: UUID())))
        clock.seconds = 10.25
        check((diagnostics.recordFirstVisualStateSubmitted(for: token)))
        #expect(diagnostics.snapshot().firstAudioStartLatency.count == 0)
        clock.seconds = 10.5
        check((diagnostics.recordFirstAudioStart(for: token)))
        clock.seconds = 20
        check((!diagnostics.recordFirstAudioStart(for: token)))
        check((!diagnostics.recordFirstVisualStateSubmitted(for: token)))
        let report = diagnostics.snapshot()
        #expect(report.turnsStarted == 1)
        #expect(report.firstAudioStartLatency.count == 1 && report.firstAudioStartLatency.meanSeconds == 0.5)
        #expect(report.firstVisualStateSubmissionLatency.count == 1 && report.firstVisualStateSubmissionLatency.maximumSeconds == 0.25)
        #expect(report.cancellationSynchronousCleanupSeconds.meanSeconds == nil)
    }

    @Test func freshNonceRejectsOldCallbacksEvenWhenCallerReusesItsIdentity() throws {
        let clock = Clock()
        var diagnostics = ExplanationDiagnostics(clock: { clock.seconds })
        let identity = UUID(), stale = try require((diagnostics.beginTurn(identity: identity)))
        clock.seconds = 1
        let current = try require((diagnostics.beginTurn(identity: identity)))
        #expect(current != stale)
        let before = diagnostics.snapshot()
        check((!diagnostics.recordFirstAudioStart(for: stale)))
        check((!diagnostics.recordFirstVisualStateSubmitted(for: stale)))
        check((!diagnostics.recordCueSchedulerLateness(for: stale, actualMediaTime: 1, dueMediaTime: 0)))
        check((!diagnostics.beginCancellation(for: stale)))
        check((!diagnostics.finishCancellation(for: stale)))
        check((!diagnostics.recordFailure(.audio, for: stale)))
        check((!diagnostics.recordProcessSample(for: stale, cumulativeCPUSeconds: 10, physicalFootprintBytes: 100)))
        check((!diagnostics.endTurn(stale)))
        #expect(diagnostics.snapshot() == before)
        clock.seconds = 1.25
        check((diagnostics.recordFirstAudioStart(for: current)))
        #expect(diagnostics.snapshot().firstAudioStartLatency.totalSeconds == 0.25)
        check((diagnostics.endTurn(current)))
        check((!diagnostics.recordFailure(.other, for: current)))
    }

    @Test func invalidAndBackwardClockReadingsCannotMutateOrReplaceTheActiveTurn() throws {
        let clock = Clock(5)
        var diagnostics = ExplanationDiagnostics(clock: { clock.seconds })
        let token = try require((diagnostics.beginTurn(identity: UUID())))
        let before = diagnostics.snapshot()
        for invalid in [Double.nan, .infinity, -.infinity, -1, 4] {
            clock.seconds = invalid
            check((diagnostics.beginTurn(identity: UUID()) == nil))
            check((!diagnostics.recordFirstAudioStart(for: token)))
            check((!diagnostics.recordFirstVisualStateSubmitted(for: token)))
            check((!diagnostics.recordCueSchedulerLateness(for: token, actualMediaTime: 1, dueMediaTime: 0)))
            check((!diagnostics.recordFailure(.provider, for: token)))
            check((!diagnostics.recordProcessSample(for: token, cumulativeCPUSeconds: 1, physicalFootprintBytes: 100)))
            check((!diagnostics.beginCancellation(for: token)))
            #expect(diagnostics.snapshot() == before)
        }
        clock.seconds = 5
        check((diagnostics.recordFirstAudioStart(for: token)))
        #expect(diagnostics.snapshot().firstAudioStartLatency.maximumSeconds == 0)
        clock.seconds = 5 + ExplanationDiagnostics.maximumIntervalSeconds + 1
        check((!diagnostics.recordFirstVisualStateSubmitted(for: token)))
        #expect(diagnostics.snapshot().firstVisualStateSubmissionLatency.count == 0)
    }

    @Test func cueLatenessIsMediaTimeNotPlaybackRateOrElapsedWallTime() throws {
        let clock = Clock()
        var diagnostics = ExplanationDiagnostics(clock: { clock.seconds })
        let token = try require((diagnostics.beginTurn(identity: UUID())))
        clock.seconds = 1_000 // Long pause/buffering does not enter the media delta.
        check((diagnostics.recordCueSchedulerLateness(for: token, actualMediaTime: 2.5, dueMediaTime: 2)))
        clock.seconds = 1_000.25
        check((diagnostics.recordCueSchedulerLateness(for: token, actualMediaTime: 2.5, dueMediaTime: 2.5)))
        let before = diagnostics.snapshot()
        for pair in [(2.0, 2.0), (3.0, 2.0), (3.0, 3.5), (-1.0, 0.0), (Double.nan, 0.0), (3.0, Double.infinity)] {
            check((!diagnostics.recordCueSchedulerLateness(for: token, actualMediaTime: pair.0, dueMediaTime: pair.1)))
            #expect(diagnostics.snapshot() == before)
        }
        let metric = before.cueSchedulerLatenessMediaSeconds
        #expect(metric.count == 2 && metric.totalSeconds == 0.5 && metric.maximumSeconds == 0.5 && metric.meanSeconds == 0.25)
    }

    @Test func cancellationMeasuresOnlyBracketedSynchronousCleanupAndClosesEventAdmission() throws {
        let clock = Clock()
        var diagnostics = ExplanationDiagnostics(clock: { clock.seconds })
        let token = try require((diagnostics.beginTurn(identity: UUID())))
        check((!diagnostics.finishCancellation(for: token)))
        clock.seconds = 20
        check((diagnostics.beginCancellation(for: token)))
        check((!diagnostics.beginCancellation(for: token)))
        check((!diagnostics.recordFirstAudioStart(for: token)))
        check((!diagnostics.recordFirstVisualStateSubmitted(for: token)))
        check((!diagnostics.recordCueSchedulerLateness(for: token, actualMediaTime: 1, dueMediaTime: 0)))
        clock.seconds = 20.125
        check((diagnostics.finishCancellation(for: token)))
        check((!diagnostics.finishCancellation(for: token)))
        check((!diagnostics.beginCancellation(for: token)))
        check((!diagnostics.recordFirstAudioStart(for: token)))
        #expect(diagnostics.snapshot().cancellationSynchronousCleanupSeconds.totalSeconds == 0.125)
        // No assertion of async teardown or when the OS stopped capture is made.
        check((diagnostics.endTurn(token)))
    }

    @Test func failedCleanupClockStillAllowsExplicitRetirementWithoutInventedTiming() throws {
        let clock = Clock(10)
        var diagnostics = ExplanationDiagnostics(clock: { clock.seconds })
        let token = try require((diagnostics.beginTurn(identity: UUID())))
        check((diagnostics.beginCancellation(for: token)))
        let before = diagnostics.snapshot()
        for invalid in [Double.nan, 9, 10 + ExplanationDiagnostics.maximumIntervalSeconds + 1] {
            clock.seconds = invalid
            check((!diagnostics.finishCancellation(for: token)))
            #expect(diagnostics.snapshot() == before)
        }
        check((diagnostics.endTurn(token)))
        clock.seconds = 11
        check((!diagnostics.finishCancellation(for: token)))
        #expect(diagnostics.snapshot().cancellationSynchronousCleanupSeconds.count == 0)
    }

    @Test func fixedFailureCategoriesCountWithoutAcceptingErrorText() throws {
        var diagnostics = ExplanationDiagnostics(clock: { 0 })
        let token = try require((diagnostics.beginTurn(identity: UUID())))
        for failure in ExplanationDiagnostics.Failure.allCases {
            check((diagnostics.recordFailure(failure, for: token)))
            #expect(diagnostics.snapshot().failures.count(for: failure) == 1)
        }
        #expect(diagnostics.snapshot().firstAudioStartLatency.count == 0)
    }

    @Test func processSamplesAreOptionalCumulativeAndAtomicOnInvalidInputs() throws {
        let clock = Clock()
        var diagnostics = ExplanationDiagnostics(clock: { clock.seconds })
        let token = try require((diagnostics.beginTurn(identity: UUID())))
        #expect(diagnostics.snapshot().processCPUSecondsDelta == nil && diagnostics.snapshot().peakPhysicalFootprintBytes == nil)
        check((!diagnostics.recordProcessSample(for: token)))
        check((diagnostics.recordProcessSample(for: token, cumulativeCPUSeconds: 10, physicalFootprintBytes: 100)))
        clock.seconds = 1
        check((diagnostics.recordProcessSample(for: token, cumulativeCPUSeconds: 12.5, physicalFootprintBytes: 90)))
        check((diagnostics.recordProcessSample(for: token, physicalFootprintBytes: 200)))
        let before = diagnostics.snapshot()
        #expect(before.processCPUSecondsDelta == 2.5 && before.peakPhysicalFootprintBytes == 200 && before.processSamples == 3)
        for invalid in [Double.nan, .infinity, -1, 12, 1_000_000_000_001] {
            check((!diagnostics.recordProcessSample(for: token, cumulativeCPUSeconds: invalid, physicalFootprintBytes: 400)))
            #expect(diagnostics.snapshot() == before)
        }
        check((!diagnostics.recordProcessSample(for: token, cumulativeCPUSeconds: 13, physicalFootprintBytes: (1 << 50) + 1)))
        #expect(diagnostics.snapshot() == before)
        check((diagnostics.endTurn(token)))
        clock.seconds = 100
        let next = try require((diagnostics.beginTurn(identity: UUID())))
        check((diagnostics.recordProcessSample(for: next, cumulativeCPUSeconds: 14)))
        #expect(diagnostics.snapshot().processCPUSecondsDelta == 4) // Includes process-wide idle gap.
        #expect(diagnostics.snapshot().peakPhysicalFootprintBytes == 200)
    }

    @Test func countersSaturateWithoutGrowingArraysOrWrapping() throws {
        var diagnostics = ExplanationDiagnostics(clock: { 0 })
        let token = try require((diagnostics.beginTurn(identity: UUID())))
        for _ in 0..<ExplanationDiagnostics.sampleLimit {
            check((diagnostics.recordCueSchedulerLateness(for: token, actualMediaTime: 1, dueMediaTime: 0)))
            check((diagnostics.recordFailure(.other, for: token)))
            check((diagnostics.recordProcessSample(for: token, physicalFootprintBytes: 1)))
        }
        let before = diagnostics.snapshot()
        check((!diagnostics.recordCueSchedulerLateness(for: token, actualMediaTime: 1, dueMediaTime: 0)))
        check((!diagnostics.recordFailure(.other, for: token)))
        check((!diagnostics.recordProcessSample(for: token, physicalFootprintBytes: 2)))
        #expect(diagnostics.snapshot() == before)
        #expect(before.cueSchedulerLatenessMediaSeconds.count == before.sampleLimit)
        #expect(before.cueSchedulerLatenessMediaSeconds.totalSeconds == Double(before.sampleLimit))
        #expect(before.failures.other == before.sampleLimit && before.processSamples == before.sampleLimit)
    }

    @Test func turnAndFirstEventAggregatesRemainBoundedAcrossReplacements() throws {
        var diagnostics = ExplanationDiagnostics(clock: { 1 })
        var last: ExplanationDiagnostics.TurnToken?
        for _ in 0..<ExplanationDiagnostics.sampleLimit {
            let token = try require((diagnostics.beginTurn(identity: UUID()))); last = token
            check((diagnostics.recordFirstAudioStart(for: token)))
            check((diagnostics.recordFirstVisualStateSubmitted(for: token)))
            check((diagnostics.beginCancellation(for: token)))
            check((diagnostics.finishCancellation(for: token)))
        }
        let before = diagnostics.snapshot()
        check((diagnostics.beginTurn(identity: UUID()) == nil))
        #expect(diagnostics.snapshot() == before)
        #expect(before.turnsStarted == before.sampleLimit && before.firstAudioStartLatency.count == before.sampleLimit)
        #expect(before.firstVisualStateSubmissionLatency.count == before.sampleLimit)
        #expect(before.cancellationSynchronousCleanupSeconds.count == before.sampleLimit)
        check((diagnostics.endTurn(try #require(last))))
    }

    @Test func encodedReportContainsOnlyFixedNumericLeavesAndNoIdentityOrAbsoluteTime() throws {
        let clock = Clock(12_345.75), identity = UUID()
        var diagnostics = ExplanationDiagnostics(clock: { clock.seconds })
        let token = try require((diagnostics.beginTurn(identity: identity)))
        clock.seconds += 0.25
        check((diagnostics.recordFirstAudioStart(for: token)))
        check((diagnostics.recordFirstVisualStateSubmitted(for: token)))
        check((diagnostics.recordProcessSample(for: token, cumulativeCPUSeconds: 900, physicalFootprintBytes: 1_024)))
        check((diagnostics.recordFailure(.provider, for: token)))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(diagnostics.snapshot())
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains(identity.uuidString) && !text.contains("12345") && !text.contains("900"))
        func requireNumericLeaves(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for child in dictionary.values { requireNumericLeaves(child) }
            } else if let number = value as? NSNumber {
                #expect(CFGetTypeID(number) != CFBooleanGetTypeID())
            } else { Issue.record("Report contained a nonnumeric leaf or collection") }
        }
        requireNumericLeaves(try JSONSerialization.jsonObject(with: encoded))
        #expect(try JSONDecoder().decode(ExplanationDiagnostics.Report.self, from: encoded) == diagnostics.snapshot())
        #expect(encoded.count < 2_048)
    }

    @Test func physicalFootprintBytesExportNamesTheProvidedMetric() throws {
        var diagnostics = ExplanationDiagnostics(clock: { 0 })
        let token = try require(diagnostics.beginTurn(identity: UUID()))
        check(diagnostics.recordProcessSample(for: token, physicalFootprintBytes: 2_048))
        #expect(diagnostics.snapshot().peakPhysicalFootprintBytes == 2_048)
        let encoded = try JSONEncoder().encode(diagnostics.snapshot())
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect((object["peakPhysicalFootprintBytes"] as? NSNumber)?.uint64Value == 2_048)
        #expect(object["peakResidentBytes"] == nil && object["residentBytes"] == nil)
    }

}
