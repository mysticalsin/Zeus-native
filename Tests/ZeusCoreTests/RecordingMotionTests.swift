import Foundation
import Testing
import ZeusCore

@Suite("Recording wing motion model")
struct RecordingMotionTests {
    typealias M = RecordingMotion

    @Test func recordlyRecordingBreathes() {
        let p = M.present(.recordly(elapsed: 3), reduceMotion: false)
        #expect(p.phase == .recording)
        #expect(p.pulse == M.breathe)
        #expect(p.stop == .available)
        #expect(p.accessibility.label == "Screen recording")
        #expect(p.accessibility.value == "3 seconds")
        #expect(p.accessibility.stopLabel == "Stop recording")
    }

    @Test func reduceMotionIsSteady() {
        let p = M.present(.recordly(elapsed: 3), reduceMotion: true)
        #expect(p.phase == .recording)
        #expect(p.pulse == .steady)
        #expect(p.stop == .available)
        for t: TimeInterval? in [nil, 0, 1, 7.3, .nan] {
            #expect(M.frame(.steady, at: t) == M.PulseFrame.steady)
        }
    }

    @Test func steadyEqualsTodaysDot() {
        #expect(M.PulseFrame.steady.opacity == 1)
        #expect(M.PulseFrame.steady.scale == 1)
        #expect(M.PulseFrame.steady.haloRadius == 0)
    }

    @Test func missingClockNeverPulses() {
        let missing: [TimeInterval?] = [nil, .nan, .infinity, -.infinity]
        for e in missing {
            let input = M.Input(producer: .recordly, isRecording: true, elapsed: e, stopAvailable: true)
            let p = M.present(input, reduceMotion: false)
            #expect(p.pulse == .steady)
            #expect(p.accessibility.value == "Elapsed time unavailable")
            #expect(M.frame(M.breathe, at: e) == M.PulseFrame.steady)
        }
    }

    @Test func breatheEndpoints() {
        let peak = M.frame(M.breathe, at: 0)
        #expect(peak.opacity == 1)
        #expect(abs(peak.scale - 1.12) < 1e-9)
        #expect(abs(peak.haloRadius - 4) < 1e-9)

        let trough = M.frame(M.breathe, at: 1.0)
        #expect(abs(trough.opacity - 0.55) < 1e-9)
        #expect(abs(trough.scale - 1) < 1e-9)
        #expect(abs(trough.haloRadius) < 1e-9)

        let again = M.frame(M.breathe, at: 2.0)
        #expect(abs(again.opacity - 1) < 1e-9)
        #expect(abs(again.scale - 1.12) < 1e-9)
        #expect(abs(again.haloRadius - 4) < 1e-9)

        var t = 0.0
        while t <= 600 {
            let f = M.frame(M.breathe, at: t)
            #expect(f.opacity >= 0.55 - 1e-9 && f.opacity <= 1 + 1e-9)
            #expect(f.scale >= 1 - 1e-9 && f.scale <= 1.12 + 1e-9)
            #expect(f.haloRadius >= -1e-9 && f.haloRadius <= 4 + 1e-9)
            t += 0.2
        }
    }

    @Test func pulseIsSlowAndWellSampled() {
        guard case let .breathe(period, _, _, _) = M.breathe else {
            Issue.record("breathe must be a .breathe spec")
            return
        }
        #expect(period >= 10 * M.sampleInterval)
        #expect(1 / period <= 1)
    }

    @Test func spokenElapsedMatchesClockRounding() {
        #expect(M.spokenElapsed(0) == "0 seconds")
        #expect(M.spokenElapsed(0.4) == "0 seconds")
        #expect(M.spokenElapsed(0.6) == "1 second")
        #expect(M.spokenElapsed(59.5) == "1 minute")
        #expect(M.spokenElapsed(65) == "1 minute, 5 seconds")
        #expect(M.spokenElapsed(3900) == "65 minutes")
        #expect(M.spokenElapsed(-5) == "0 seconds")
        #expect(M.spokenElapsed(.nan) == nil)
        #expect(M.spokenElapsed(.infinity) == nil)
    }

    @Test func notRecordingIsInactive() {
        let input = M.Input(producer: .recordly, isRecording: false, elapsed: 5, stopAvailable: true)
        let p = M.present(input, reduceMotion: false)
        #expect(p.phase == .inactive)
        #expect(p.pulse == .steady)
        #expect(p.stop == .unavailable)
        #expect(p.accessibility.value == "Not recording")
    }

    @Test func meetingFixtureIsHonest() {
        let fixture = M.Input(producer: .meetingFixture, isRecording: true, elapsed: nil, stopAvailable: false)
        let p = M.present(fixture, reduceMotion: false)
        #expect(p.accessibility.label == "Meeting recording (preview)")
        #expect(p.pulse == .steady)
        #expect(p.stop == .unavailable)
        #expect(p.accessibility.value == "Elapsed time unavailable")

        let banned = ["transcript", "notes", "final", "complete", "mute", "saved"]
        for producer in M.Producer.allCases {
            for isRecording in [true, false] {
                for elapsed: TimeInterval? in [nil, 0, 65, 3900] {
                    let input = M.Input(producer: producer, isRecording: isRecording, elapsed: elapsed, stopAvailable: true)
                    let a = M.present(input, reduceMotion: false).accessibility
                    for s in [a.label, a.value, a.stopLabel, a.stopHint] {
                        for word in banned {
                            #expect(!s.lowercased().contains(word), "\"\(s)\" contains \"\(word)\"")
                        }
                    }
                }
            }
        }
    }

    @Test func stopHintPromisesNothing() {
        let a = M.present(.recordly(elapsed: 1), reduceMotion: false).accessibility
        #expect(a.stopHint == "Stops the screen recording.")
    }
}
