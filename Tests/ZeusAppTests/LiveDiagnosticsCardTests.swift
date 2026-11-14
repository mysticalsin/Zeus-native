import AppKit
import Combine
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The card samples through `EnergyMonitor` only while it is on screen in a window that can be seen.
/// These pin the monitor's fresh-start contract, the hold that keeps start and stop balanced, and the
/// window reading that stops sampling when the retained Settings window is closed or minimised.
@MainActor @Suite("Live diagnostics card", .serialized)
struct LiveDiagnosticsCardTests {
    // MARK: EnergyMonitor

    @Test func theCpuSampleFlagIsFalseFromEveryFreshStartUntilTheFirstSample() {
        let monitor = EnergyMonitor.shared
        monitor.start()
        #expect(monitor.isSampling)
        #expect(!monitor.hasCPUSample)
        monitor.sample()
        #expect(monitor.hasCPUSample)
        monitor.stop()
        #expect(!monitor.isSampling)
        monitor.start()
        #expect(!monitor.hasCPUSample)
        monitor.stop()
        #expect(!monitor.isSampling)
    }

    @Test func aSecondViewerKeepsTheTimerAndTheSampleFlag() {
        let monitor = EnergyMonitor.shared
        monitor.start()
        monitor.sample()
        monitor.start()
        #expect(monitor.hasCPUSample)
        monitor.stop()
        #expect(monitor.isSampling)
        monitor.stop()
        #expect(!monitor.isSampling)
    }

    // MARK: SamplingHold

    private final class Counter {
        var starts = 0
        var stops = 0
    }

    private func hold(_ counter: Counter) -> SamplingHold {
        SamplingHold(start: { counter.starts += 1 }, stop: { counter.stops += 1 })
    }

    @Test func theHoldStartsOnlyWhenShownAndInAVisibleWindow() {
        let counter = Counter()
        let hold = hold(counter)
        #expect(!hold.isHolding)
        hold.appear()
        #expect(hold.isHolding && counter.starts == 1)
        hold.windowVisibility(false)   // the Settings window was closed or minimised
        #expect(!hold.isHolding && counter.stops == 1)
        hold.windowVisibility(true)    // and came back
        #expect(hold.isHolding && counter.starts == 2)
        hold.disappear()
        #expect(!hold.isHolding && counter.stops == 2)
    }

    @Test func theHoldStaysBalancedWhateverOrderTheEventsComeIn() {
        let counter = Counter()
        let hold = hold(counter)
        hold.windowVisibility(false)
        hold.appear()
        #expect(counter.starts == 0)   // shown, but nobody can see it
        hold.windowVisibility(false)
        hold.windowVisibility(true)
        hold.windowVisibility(true)
        hold.appear()
        hold.disappear()
        hold.disappear()
        hold.windowVisibility(false)
        hold.windowVisibility(true)
        #expect(counter.starts == 1 && counter.stops == 1)
        #expect(!hold.isHolding)
    }

    @Test func aHoldGoneWithoutDisappearReleasesTheMonitor() {
        let counter = Counter()
        var hold: SamplingHold? = self.hold(counter)
        hold?.appear()
        #expect(counter.starts == 1 && counter.stops == 0)
        hold = nil
        #expect(counter.stops == 1)
    }

    @Test func closingTheWindowStopsTheRealMonitorsTimer() {
        let monitor = EnergyMonitor.shared
        let hold = SamplingHold(start: { monitor.start() }, stop: { monitor.stop() })
        hold.appear()
        #expect(monitor.isSampling)
        hold.windowVisibility(false)
        #expect(!monitor.isSampling)
        hold.windowVisibility(true)
        #expect(monitor.isSampling)
        hold.disappear()
        #expect(!monitor.isSampling)
    }

    // MARK: Window reading

    private func window() -> NSWindow {
        _ = NSApplication.shared
        return NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 40), styleMask: [.titled],
                        backing: .buffered, defer: true)
    }

    @Test func aWindowThatIsNotOrderedInReadsHiddenAndCloseAlwaysReadsHidden() {
        let window = window()
        window.isReleasedWhenClosed = false
        #expect(!WindowVisibility.isVisible(window))
        #expect(!WindowVisibility.isVisible(nil))
        #expect(!WindowVisibility.reading(after: NSWindow.willCloseNotification, in: window))
        #expect(!WindowVisibility.reading(after: NSWindow.didBecomeKeyNotification, in: window))
        #expect(WindowVisibility.changeNotifications.contains(NSWindow.willCloseNotification))
        #expect(WindowVisibility.changeNotifications.contains(NSWindow.didMiniaturizeNotification))
        #expect(WindowVisibility.changeNotifications.contains(NSWindow.didDeminiaturizeNotification))
        #expect(WindowVisibility.changeNotifications.contains(NSWindow.didChangeOcclusionStateNotification))
    }

    @Test func theReaderReportsWhenItJoinsAWindowAndWhenThatWindowCloses() {
        let window = window()
        window.isReleasedWhenClosed = false
        var reports: [Bool] = []
        let reader = WindowVisibilityReader.ReaderView { reports.append($0) }
        window.contentView = reader
        #expect(reports == [false])
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        #expect(reports == [false, false])
        window.contentView = NSView()   // the reader leaves the window and stops listening
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        #expect(reports.count == 3)
    }

    // MARK: Occlusion

    @Test func samplingStopsWhenTheWindowIsOrderedInButCoveredOrOnAnotherSpace() {
        #expect(SamplingVisibility.isSeen(ordered: true, occlusionVisible: true))
        #expect(!SamplingVisibility.isSeen(ordered: true, occlusionVisible: false))
        #expect(!SamplingVisibility.isSeen(ordered: false, occlusionVisible: true))
        #expect(!SamplingVisibility.isSeen(ordered: false, occlusionVisible: false))
    }

    @Test func aWindowThatIsNotShownIsNeverSeenAndCloseAlwaysReadsHidden() {
        let window = window()
        window.isReleasedWhenClosed = false
        #expect(!SamplingVisibility.isSeen(window))
        #expect(!SamplingVisibility.isSeen(nil))
        #expect(!SamplingVisibility.reading(after: NSWindow.willCloseNotification, in: window))
        #expect(!SamplingVisibility.reading(after: NSWindow.didChangeOcclusionStateNotification, in: window))
    }

    // MARK: Thermal delivery

    @Test func theThermalNotificationReachesTheCardOnTheMainThread() async {
        let center = NotificationCenter()
        var cancellable: AnyCancellable?
        let onMain: Bool = await withCheckedContinuation { continuation in
            cancellable = LiveDiagnosticsCard.thermalChanges(center: center).sink { continuation.resume(returning: Thread.isMainThread) }
            // Foundation posts this notification from a global queue.
            DispatchQueue.global().async { center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil) }
        }
        cancellable?.cancel()
        #expect(onMain)
    }

    // MARK: Copy

    @Test func copyPutsTheSummaryOnThePasteboardAndAnnouncesIt() {
        let board = NSPasteboard(name: NSPasteboard.Name("zeus.diagnostics.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let live = LiveDiagnostics(cpuPercent: 0.4, memoryBytes: 96 * 1_048_576, thermal: .nominal, audio: .off,
                                   playerName: "Music", isPlaying: true, appVersion: "1.0", build: "1", osVersion: "26.0.0")
        var spoken: [String] = []
        LiveDiagnosticsCard.copy(live, to: board) { spoken.append($0) }
        #expect(board.string(forType: .string) == live.summaryText)
        #expect(spoken == [LiveDiagnosticsCard.copiedAnnouncement])
        #expect(!LiveDiagnosticsCard.copiedAnnouncement.isEmpty)
    }
}
