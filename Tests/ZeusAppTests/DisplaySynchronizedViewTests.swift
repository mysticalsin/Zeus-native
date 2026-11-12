import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Owned hidden native resources only. This is lifecycle proof, not a displayed-240Hz benchmark.
@MainActor @Suite("Display link native lifecycle", .serialized)
struct DisplaySynchronizedViewTests {
    @Test func ownerPauseReducedMotionAndDetachInvalidateTheOwnedDisplayLink() throws {
        _ = NSApplication.shared
        let clock = DisplayAnimationClock()
        let probe = DisplayAnimationProbeView(clock: clock)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = probe
        defer { probe.detach(); window.contentView = nil; window.close() }
        let screen = try #require(window.screen, "The native host must expose its real screen capability")
        clock.configure(paused: false, reduceMotion: false, preferredFramesPerSecond: 240)
        clock.appear()
        #expect(probe.hasDisplayLink)
        #expect(probe.requestedFramesPerSecond == min(screen.maximumFramesPerSecond, 240))
        #expect(!window.isVisible && !probe.mayPublish)

        clock.configure(paused: true, reduceMotion: false, preferredFramesPerSecond: 240)
        #expect(!probe.hasDisplayLink)
        clock.configure(paused: false, reduceMotion: true, preferredFramesPerSecond: 240)
        #expect(!probe.hasDisplayLink)
        clock.configure(paused: false, reduceMotion: false, preferredFramesPerSecond: 240)
        #expect(probe.hasDisplayLink)

        // KVO responds to alpha changes without a timer that polls an invisible window.
        window.alphaValue = 0
        #expect(probe.isDisplayLinkPaused)
        window.alphaValue = 1
        #expect(!probe.isDisplayLinkPaused)
        probe.isHidden = true
        #expect(probe.isDisplayLinkPaused)
        probe.isHidden = false
        #expect(!probe.isDisplayLinkPaused)

        clock.configure(paused: false, reduceMotion: false, preferredFramesPerSecond: 240, until: .distantPast)
        #expect(!probe.hasDisplayLink)
        let deadline = Date().addingTimeInterval(10)
        clock.configure(paused: false, reduceMotion: false, preferredFramesPerSecond: 240, until: deadline)
        #expect(probe.hasDisplayLink)
        clock.settleExpiredDeadline(at: deadline, notify: true)
        #expect(!probe.hasDisplayLink && !clock.wantsLink)
        #expect(clock.presentationContext(at: deadline.addingTimeInterval(-0.001), staticFrame: false).date == deadline)
        clock.configure(paused: false, reduceMotion: false, preferredFramesPerSecond: 240, until: deadline.addingTimeInterval(10))
        #expect(probe.hasDisplayLink)

        window.contentView = nil
        #expect(!probe.hasDisplayLink)
        clock.disappear()
        #expect(!probe.hasDisplayLink && clock.metrics.callbackCount == 0)
    }

    @Test func pausedAndReducedClockUsesFreshTimeForNewCompletionWithoutStartingALink() {
        let clock = DisplayAnimationClock()
        let oldDate = clock.context.date
        for reduced in [false, true] {
            clock.configure(paused: !reduced, reduceMotion: reduced, preferredFramesPerSecond: 240)
            clock.appear()
            let newDate = oldDate.addingTimeInterval(20)
            let snapshot = RecordingFeedback.Snapshot(producer: .meetings, phase: .completed, sessionKey: "fixture",
                beganAt: newDate.timeIntervalSinceReferenceDate - 1, label: "Meeting saved")
            let context = clock.presentationContext(at: newDate, staticFrame: true)
            #expect(context.date == newDate)
            let frame = RecordingFeedback.frame(snapshot, at: context.date.timeIntervalSinceReferenceDate,
                                                 reduceMotion: reduced, reduceTransparency: false)
            #expect(frame.visible && frame.reveal == 1)
            // A frozen timestamp would be before this completion and make it disappear.
            #expect(!RecordingFeedback.frame(snapshot, at: oldDate.timeIntervalSinceReferenceDate,
                                               reduceMotion: reduced, reduceTransparency: false).visible)
            #expect(!clock.wantsLink && clock.metrics.callbackCount == 0)
            clock.disappear()
        }
    }
}
