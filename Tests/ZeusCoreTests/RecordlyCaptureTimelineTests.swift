import Testing
@testable import ZeusCore

@Suite("Recordly capture timeline")
struct RecordlyCaptureTimelineTests {
    @Test func hostUptimeDoesNotBecomeMovieLeadIn() {
        var timeline = RecordlyCaptureTimeline()
        #expect(timeline.admit(presentationTime: 86_400, isVideo: true) == .startSession)
        #expect(timeline.admit(presentationTime: 86_402, isVideo: true) == .append)
        #expect(timeline.elapsed(at: 86_402) == 2)
    }

    @Test func audioCannotStartSessionOrPrecedeFirstVideo() {
        var timeline = RecordlyCaptureTimeline()
        #expect(timeline.admit(presentationTime: 99, isVideo: false) == .drop)
        #expect(timeline.origin == nil)
        #expect(timeline.admit(presentationTime: 100, isVideo: true) == .startSession)
        #expect(timeline.admit(presentationTime: 99.9, isVideo: false) == .drop)
        #expect(timeline.admit(presentationTime: 100.1, isVideo: false) == .append)
    }

    @Test func malformedSamplesAndCursorTimesAreRejected() {
        var timeline = RecordlyCaptureTimeline()
        for time in [Double.nan, .infinity, -.infinity, -1] {
            #expect(timeline.admit(presentationTime: time, isVideo: true) == .drop)
        }
        #expect(timeline.elapsed(at: 10) == nil)
        #expect(timeline.admit(presentationTime: 10, isVideo: true) == .startSession)
        #expect(timeline.elapsed(at: 9) == nil)
        #expect(timeline.elapsed(at: .nan) == nil)
        #expect(timeline.elapsed(at: 10) == 0)
    }

    @Test func aNewRecordingGetsANewOrigin() {
        var first = RecordlyCaptureTimeline()
        _ = first.admit(presentationTime: 100, isVideo: true)
        var second = RecordlyCaptureTimeline()
        #expect(second.admit(presentationTime: 900, isVideo: true) == .startSession)
        #expect(second.elapsed(at: 901) == 1)
        #expect(first.origin == 100)
    }
}
