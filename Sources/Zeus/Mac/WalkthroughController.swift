import AppKit
import ZeusCore

@MainActor
final class WalkthroughController {
    static let shared = WalkthroughController()

    private(set) var session: WalkthroughSession?
    private var shots: [ScreenShot] = []
    private var resolved: GuidedPresent.ResolvedTarget?
    private var clickMonitor: Any?
    private var escMonitor: Any?
    private var autoAdvance: Task<Void, Never>?
    private var clickAdvance: Task<Void, Never>?
    weak var buddy: BuddyController?
    var say: ((String) -> Void)?

    var isRunning: Bool { session?.state == .running }

    func start(_ walkthrough: Walkthrough, screenshots: [ScreenShot]) {
        stop()
        session = WalkthroughSession(walkthrough)
        shots = screenshots
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            MainActor.assumeIsolated { WalkthroughController.shared.clicked(at: NSEvent.mouseLocation) }
        }
        if AccessibilityGate.trusted {
            escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { MainActor.assumeIsolated { WalkthroughController.shared.cancel() } }
            }
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
        say?("Okay, tour stopped.")
        stop()
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
            say?("That's it, you're done.")
            stop()
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
        if let target = resolved {
            buddy?.point(to: target.screenPoint, label: target.label)
        }
        say?("\(session.progress). \(step.say)")
        if !step.waitForClick || (step.target == nil && step.targetLabel == nil) {
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
        [clickMonitor, escMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        clickMonitor = nil
        escMonitor = nil
        buddy?.idle()
        session = nil
        resolved = nil
    }
}
