import Foundation
import Observation

/// A section the session can run. There is no live default: the caller passes one.
@MainActor
public protocol StepZeroSection: AnyObject {
    func run() async
}

/// One window's state. A section's `run` starts only from Continue, and only after
/// the 1.5 second dead period has been armed. Skip does not call `run`.
///
/// The limit is the seconds the caller already chose. When that generation fires
/// and the part has not finished, the watchdog's record is kept and the part stops.
/// A later return from `run` does not replace that stop with Done.
@MainActor
@Observable
public final class StepZeroSession {
    /// Continue stays dead for this long after the window appears. 1500 is 1.5 seconds.
    public static let continueDeadMilliseconds = 1500

    public private(set) var armed = false
    public private(set) var phase: StepZeroView.Word = .notRun
    public private(set) var fire: StepZeroWatchdog.Fire?
    public let limitSeconds: Int

    @ObservationIgnored private let section: any StepZeroSection
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var currentArm: StepZeroWatchdog.Arm?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var ended = false

    public init(section: any StepZeroSection, limitSeconds: Int) {
        self.section = section
        self.limitSeconds = limitSeconds
    }

    public var generation: Int? { currentArm?.generation }

    /// Ends the dead period and arms the one timer. A second call keeps the same arm.
    public func arm() {
        guard !armed else { return }
        armed = true
        currentArm = StepZeroWatchdog.arm(seconds: limitSeconds, after: nil)
    }

    /// Dropped until `arm()`. After that, starts the injected section once.
    public func continuePressed() {
        guard armed, !started, !ended, limitSeconds > 0, currentArm != nil else { return }
        started = true
        phase = .running
        let section = self.section
        task = Task { @MainActor in
            await section.run()
            self.finishIfStillRunning()
        }
    }

    /// Records skipped and does not call the section.
    public func skipPressed() {
        guard !started, !ended else { return }
        ended = true
        phase = .skipped
    }

    /// The current arm fired. Any other generation is ignored.
    public func limitElapsed(generation: Int) {
        guard started, !ended else { return }
        guard let fired = StepZeroWatchdog.fire(generation: generation, current: currentArm) else { return }
        ended = true
        task?.cancel()
        phase = .stopped
        fire = fired
    }

    private func finishIfStillRunning() {
        guard !ended else { return }
        ended = true
        phase = .done
    }
}
