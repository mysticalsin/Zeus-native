import AppKit
import ZeusCore

@MainActor
final class WalkthroughController {
    static let shared = WalkthroughController()

    private(set) var session: WalkthroughSession?
    private var shots: [ScreenShot] = []
    private var resolved: GuidedPresent.ResolvedTarget?
    private var clickMonitors: [Any] = []
    private var escMonitors: [Any] = []
    private var autoAdvance: Task<Void, Never>?
    private var clickAdvance: Task<Void, Never>?
    weak var buddy: BuddyController?
    var say: ((String) -> Void)?

    var isRunning: Bool { session?.state == .running }

    func start(_ walkthrough: Walkthrough, screenshots: [ScreenShot]) {
        stop()
        session = WalkthroughSession(walkthrough)
        shots = screenshots
        let click: (NSEvent) -> Void = { _ in
            MainActor.assumeIsolated { WalkthroughController.shared.clicked(at: NSEvent.mouseLocation) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: click) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { event in
            click(event)
            return event
        }) {
            clickMonitors.append(local)
        }
        let escape: (NSEvent) -> Void = { event in
            if event.keyCode == 53 { MainActor.assumeIsolated { WalkthroughController.shared.cancel() } }
        }
        if AccessibilityGate.trusted,
           let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: escape) {
            escMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            escape(event)
            return event
        }) {
            escMonitors.append(local)
        }
        NSLog("[ZEUS] walkthrough: start \"%@\" steps=%d", walkthrough.title, walkthrough.steps.count)
        present()
    }

    /// Voice: "next", "back", "stop". Returns true when the words were for the tour.
    func handle(transcript: String) -> Bool {
        guard isRunning, let command = WalkthroughSession.command(for: transcript) else { return false }
        switch command {
        case "next": advance(force: true)
        case "back":
            if var s = session { s.back(); session = s }
            present()
        default: cancel()
        }
        return true
    }

    func cancel() {
        guard isRunning else { return }
        session?.cancel()
        NSLog("[ZEUS] walkthrough: cancelled")
        stop()
        say?("Okay, tour stopped.")
    }

    private func clicked(at point: CGPoint) {
        guard isRunning, let target = resolved, let revision = session?.revision, clickAdvance == nil else { return }
        guard target.waitForClick else { return }
        guard GuidedPresent.clickHits(point, target: target) else {
            NSLog("[ZEUS] walkthrough: ignored click outside target")
            return
        }
        clickAdvance = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self.clickAdvance = nil
            self.advance(force: true, revision: revision)
        }
    }

    private func advance(force: Bool, revision: UUID? = nil) {
        guard var session else { return }
        if let step = session.current, step.waitForClick,
           (step.target != nil || step.targetLabel != nil), !force { return }
        if let revision {
            guard session.next(ifRevision: revision) else { return }
        } else {
            session.next()
        }
        self.session = session
        if session.state == .finished {
            NSLog("[ZEUS] walkthrough: finished")
            stop()
            say?("That's it, you're done.")
        } else {
            present()
        }
    }

    private func present() {
        autoAdvance?.cancel()
        clickAdvance?.cancel()
        clickAdvance = nil
        guard let session, let step = session.current else { return }
        let snapshot = AXSnapshotter.shared.latest
        resolved = GuidedPresent.resolve(step: step, shots: shots, snapshot: snapshot)
        NSLog("[ZEUS] walkthrough: %@", session.progress)
        let cue = step.cue(progress: session.progress, found: resolved != nil)
        if let target = resolved {
            let label = PointerGuideCaptionSplit.boltText(target.label)
                ?? PointerGuideCaptionSplit.boltText(step.say)
                ?? "Here"
            buddy?.point(to: target.screenPoint, label: label, ring: target.hitRect)
        } else if let bolt = cue.bolt {
            buddy?.showCaption(bolt)
        }
        say?(cue.spoken)
        if !step.holdsForClick(found: resolved != nil) {
            let revision = session.revision
            autoAdvance = Task { @MainActor in
                try? await Task.sleep(for: .seconds(4 + Double(step.say.count) / 15))
                guard !Task.isCancelled else { return }
                self.advance(force: true, revision: revision)
            }
        }
    }

    private func stop() {
        autoAdvance?.cancel()
        clickAdvance?.cancel()
        clickAdvance = nil
        (clickMonitors + escMonitors).forEach(NSEvent.removeMonitor)
        clickMonitors.removeAll()
        escMonitors.removeAll()
        buddy?.idle()
        session = nil
        resolved = nil
    }
}
