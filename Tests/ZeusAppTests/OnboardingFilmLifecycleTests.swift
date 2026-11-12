import AppKit
import AVFoundation
import Foundation
import Testing
@testable import Zeus

/// Owned windows and the actual muted AVQueuePlayer with bundled local video. No capture, sound,
/// global input, private media or fake playback counters. This does not measure decoder CPU/energy.
@MainActor @Suite("Onboarding film native lifecycle", .serialized)
struct OnboardingFilmLifecycleTests {
    private func waitFor(_ description: String, view: LoopingFilm.FilmView, timeout: Duration = .seconds(4),
                         _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition(), "Film lifecycle did not reach \(description): \(view.playbackState)")
    }

    private func requireAdvancing(_ view: LoopingFilm.FilmView) async throws {
        try await waitFor("actual player playing", view: view) {
            let state = view.playbackState
            return state.muted && state.rate > 0 && state.status == .playing && state.seconds.isFinite
        }
        let began = view.playbackState.seconds
        try await waitFor("advancing media time", view: view) {
            let state = view.playbackState
            // A genuine loop boundary also advances playback; do not require monotonic media time.
            return state.status == .playing && state.rate > 0 && state.seconds.isFinite
                && abs(state.seconds - began) > 0.08
        }
    }

    private func requirePaused(_ view: LoopingFilm.FilmView) async throws {
        try await waitFor("actual player paused", view: view) {
            let state = view.playbackState
            return state.rate == 0 && state.status == .paused
        }
        let pausedAt = view.playbackState.seconds
        try #require(pausedAt.isFinite)
        try await Task.sleep(for: .milliseconds(150))
        let later = view.playbackState
        #expect(later.rate == 0 && later.status == .paused)
        #expect(later.seconds.isFinite && abs(later.seconds - pausedAt) <= 0.02,
                "A paused decorative film must not continue advancing")
    }

    private func makeWindow(frame: NSRect? = nil) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 40, y: 100, width: 360, height: 240),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Synthetic muted onboarding film"
        window.isReleasedWhenClosed = false
        if let frame { window.setFrame(frame, display: false) }
        return window
    }

    private func withFilm(_ films: [OnboardingFilm] = [.running],
                          operation: @MainActor (LoopingFilm.FilmView, NSWindow) async throws -> Void) async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            for film in films {
                let url = try #require(film.url, "Require shipped video, not a dummy player")
                try #require(url.isFileURL && FileManager.default.fileExists(atPath: url.path))
            }
            let view = LoopingFilm.FilmView(films: films)
            let window = makeWindow()
            window.contentView = view
            defer {
                if NSApplication.shared.isHidden { NSApplication.shared.unhide(nil) }
                LoopingFilm.dismantleNSView(view, coordinator: ())
                OwnedWindowFixtureApplication.close(window)
            }
            #expect(view.playbackState.muted)
            #expect(view.playbackState.rate == 0 && view.playbackState.status == .paused)
            window.makeKeyAndOrderFront(nil)
            try await waitFor("visible unoccluded window", view: view) {
                window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
            }
            // A missing usable native surface cannot be replaced by a simulated play callback.
            try await requireAdvancing(view)
            try await operation(view, window)
        }
    }

    @Test func actualPlayerPausesForMiniaturizationHiddenAppAndOrderedOutWindow() async throws {
        try await withFilm { view, window in
            window.miniaturize(nil)
            try await waitFor("miniaturized window", view: view) { window.isMiniaturized }
            try await requirePaused(view)
            window.deminiaturize(nil)
            try await waitFor("restored window", view: view) {
                !window.isMiniaturized && window.occlusionState.contains(.visible)
            }
            try await requireAdvancing(view)

            NSApplication.shared.hide(nil)
            try await waitFor("hidden fixture application", view: view) { NSApplication.shared.isHidden }
            try await requirePaused(view)
            NSApplication.shared.unhide(nil)
            try await waitFor("unhidden fixture application", view: view) { !NSApplication.shared.isHidden }
            try await requireAdvancing(view)

            window.orderOut(nil)
            try await waitFor("ordered-out window", view: view) { !window.isVisible }
            try await requirePaused(view)
            window.makeKeyAndOrderFront(nil)
            try await requireAdvancing(view)

            window.close() // Actual retained-window close, followed by its supported reopen.
            try await waitFor("closed window", view: view) { !window.isVisible }
            try await requirePaused(view)
            window.makeKeyAndOrderFront(nil)
            try await requireAdvancing(view)
        }
    }

    @Test func actualOcclusionHiddenViewAndReducedMotionPausePlayback() async throws {
        try await withFilm { view, window in
            let cover = NSWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            cover.isReleasedWhenClosed = false
            cover.isOpaque = true
            cover.backgroundColor = .black
            cover.hasShadow = false
            cover.level = .floating
            defer { OwnedWindowFixtureApplication.close(cover) }
            cover.orderFrontRegardless()
            try await waitFor("actual complete occlusion by the owned cover", view: view) {
                !window.occlusionState.contains(.visible)
            }
            try await requirePaused(view)
            cover.orderOut(nil)
            try await requireAdvancing(view)

            view.isHidden = true
            try await requirePaused(view)
            view.isHidden = false
            try await requireAdvancing(view)

            view.setReducedMotion(true) // The same view update used by NSViewRepresentable.
            try await requirePaused(view)
            view.setReducedMotion(false) // Never overrides the person's OS Reduce Motion preference.
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { try await requirePaused(view) }
            else { try await requireAdvancing(view) }
        }
    }

    @Test func reattachmentIgnoresOldWindowAndDisposalCannotRestartPlayback() async throws {
        try await withFilm { view, first in
            let second = makeWindow(frame: first.frame)
            defer { OwnedWindowFixtureApplication.close(second) }
            first.contentView = nil
            try await requirePaused(view)
            #expect(view.playbackState.observerCount == 0)
            second.contentView = view
            second.makeKeyAndOrderFront(nil)
            try await requireAdvancing(view)
            let attachedObservers = view.playbackState.observerCount
            #expect(attachedObservers > 0)
            first.close()
            try await requireAdvancing(view)
            #expect(view.playbackState.observerCount == attachedObservers)

            LoopingFilm.dismantleNSView(view, coordinator: ())
            let disposed = view.playbackState
            #expect(disposed.disposed && disposed.queuedItems == 0 && disposed.trackedItems == 0 && disposed.observerCount == 0)
            #expect(disposed.rate == 0 && disposed.status == .paused)
            // Later native visibility changes and representable updates cannot revive disposed media.
            second.orderOut(nil)
            second.makeKeyAndOrderFront(nil)
            view.setReducedMotion(false)
            try await Task.sleep(for: .milliseconds(150))
            #expect(view.playbackState.disposed && view.playbackState.queuedItems == 0)
            #expect(view.playbackState.rate == 0 && view.playbackState.status == .paused)
        }
    }

    @Test func onlyOwnedNaturalCompletionsCanRequeueBundledFilms() async throws {
        try await withFilm([.approve, .previews]) { view, _ in
            let initial = view.playbackState
            #expect(initial.queuedFilms == ["learn-approve.mp4", "learn-previews.mp4"])
            #expect(initial.trackedItems == 2 && initial.queuedItems == 2)
            let foreign = AVPlayerItem(url: try #require(OnboardingFilm.approve.url))
            for _ in 0..<3 {
                NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: foreign)
            }
            #expect(view.playbackState.queuedFilms == initial.queuedFilms)
            #expect(view.playbackState.trackedItems == 2 && view.playbackState.queuedItems == 2)

            // Let the actual five-second bundled film finish; never forge an owned completion.
            try await waitFor("natural owned completion and bounded requeue", view: view, timeout: .seconds(8)) {
                let state = view.playbackState
                return state.queuedFilms == ["learn-previews.mp4", "learn-approve.mp4"]
                    && state.queuedItems == 2 && state.trackedItems == 2
            }
            try await requireAdvancing(view)
            LoopingFilm.dismantleNSView(view, coordinator: ())
            NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: foreign)
            #expect(view.playbackState.queuedItems == 0 && view.playbackState.trackedItems == 0)
        }
    }
}
