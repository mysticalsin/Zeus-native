import Foundation

/// Holds the click window for every top-bar summary. The decision is `TopBarWidgetClicks`. This sleeps
/// until the date that decision returned. The clock and the sleeper are passed in, so a test does not wait
/// on the wall clock. The app leaves both on the wall clock.
@MainActor
public final class TopBarWidgetClickSession {
    /// How long to wait. Tests record the duration and return without a real timer.
    public typealias Sleeper = @MainActor @Sendable (Duration) async -> Void

    private var clicks = TopBarWidgetClicks()
    private var wake: Task<Void, Never>?
    public var now: @MainActor () -> Date = { Date() }
    public var sleep: Sleeper = { _ = try? await Task.sleep(for: $0) }

    public init() {}

    public func tap(_ target: TopBarWidgetTarget, apply: @escaping (TopBarWidgetEffect) -> Void) {
        let step = clicks.click(target, at: now())
        for effect in step.effects { apply(effect) }
        arm(step.arm, apply: apply)
    }

    public func activate(_ target: TopBarWidgetTarget, apply: (TopBarWidgetEffect) -> Void) {
        wake?.cancel()
        wake = nil
        let step = clicks.activate(target)
        for effect in step.effects { apply(effect) }
    }

    public func showDetails(_ target: TopBarWidgetTarget) -> TopBarWidgetEffect? {
        wake?.cancel()
        wake = nil
        return clicks.showDetails(target)
    }

    private func arm(_ until: Date?, apply: @escaping (TopBarWidgetEffect) -> Void) {
        wake?.cancel()
        wake = nil
        guard let until else { return }
        let delay = until.timeIntervalSince(now())
        let sleep = sleep
        wake = Task { @MainActor [weak self] in
            if delay > 0 { await sleep(.seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            self.wake = nil
            let settled = self.clicks.tick(at: self.now())
            for effect in settled.effects { apply(effect) }
            self.arm(settled.arm, apply: apply)
        }
    }
}
