import Darwin
import Foundation
import ZeusCore

// What the equaliser controller needs from the Mac, as small protocols. The live types sit beside the code that
// uses Core Audio; tests give the controller fakes, so no test ever creates a tap or opens a listener.

/// The default output as the engine needs to judge it.
struct EqualiserOutputFacts: Equatable, Sendable {
    var uid: String
    var format: EqualiserStreamFormat
    /// An aggregate or multi-output device, which the engine never renders to.
    var isAggregate: Bool
    /// The output channels that carry the left and right of a stereo pair, zero-based.
    var stereoLeft = 0
    var stereoRight = 1
}

/// Everything one read of the world gives.
struct EqualiserReading: Equatable, Sendable {
    var processes: [AudioProcessFacts] = []
    var runningAppBundleIDs: [String] = []
    /// Display names by bundle id, for the apps that are running.
    var names: [String: String] = [:]
    /// Nil when the Mac has no default output.
    var output: EqualiserOutputFacts?
}

/// What a listener saw change. The controller reads the world again to learn the rest.
enum EqualiserMonitorEvent: Sendable, Equatable {
    case processes
    /// The default output device is another one.
    case output
    /// The default output's rate or layout changed.
    case format
    /// The default output device went away.
    case deviceGone
}

@MainActor
protocol EqualiserMonitoring: AnyObject {
    var onEvent: (@MainActor (EqualiserMonitorEvent) -> Void)? { get set }
    /// Install the listeners. Nothing is installed before this.
    func start()
    /// Remove every listener.
    func stop()
    func read() -> EqualiserReading
    func pidIsAlive(_ pid: Int32) -> Bool
}

/// What one tap or probe is built for.
struct ShapingRequest: Sendable {
    let group: EqualiserProcessGroup
    let displayName: String
    let output: EqualiserOutputFacts
    let parameters: EqualiserParameters
}

/// Why a tap or probe could not be built.
enum ShapingFailure: Error, Equatable, Sendable {
    /// The Mac has no default output any more.
    case noOutput
    /// The tap or output format cannot be rendered; the engine pauses instead of muting.
    case unsupported(reason: String)
    /// A Core Audio call failed at `stage` with `status`.
    case system(stage: String, status: Int32)

    var status: Int32 {
        if case .system(_, let status) = self { return status }
        return 0
    }

    /// A failure that is not one app's: the tap call itself is refused, or there is no output.
    var isEngineWide: Bool {
        switch self {
        case .noOutput: return true
        case .system(let stage, _): return stage == "tap"
        case .unsupported: return false
        }
    }
}

/// Counters the render callback keeps and the main thread reads.
struct ShapingMeterReading: Equatable, Sendable {
    var callbacks: Int64
    var frames: Int64
    /// Frames in which every channel of the tap was exactly zero.
    var zeroFrames: Int64
}

@MainActor
protocol ShapingTapHandle: AnyObject {
    var sampleRate: Double { get }
    var meter: ShapingMeterReading { get }
    func post(_ parameters: EqualiserParameters)
    /// Write the tap's process list again. False when the write failed.
    func retarget(objectIDs: [UInt32]) -> Bool
    /// Destroys everything this tap built, in order, and waits for the last callback.
    func stop()
}

@MainActor
protocol ShapingProbeHandle: AnyObject {
    var meter: ShapingMeterReading { get }
    func stop()
}

@MainActor
protocol ShapingTapFactory: AnyObject {
    /// A muted-when-tapped tap that renders the app to the current output.
    func makeTap(_ request: ShapingRequest) throws -> any ShapingTapHandle
    /// A listen-only tap. Nothing is muted and nothing is played.
    func makeProbe(_ request: ShapingRequest) throws -> any ShapingProbeHandle
    /// Destroys any aggregate a crashed run left behind. Returns how many.
    func sweepLeftovers() -> Int
}

/// The one right to shape sound on this Mac, so two copies of Zeus never double an app.
@MainActor
protocol EqualiserClaiming: AnyObject {
    func take() -> Bool
    func release()
}

/// A timer the controller can cancel.
@MainActor
final class EqualiserTimer {
    private var onCancel: (@MainActor () -> Void)?

    init(onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }
}

@MainActor
protocol EqualiserScheduling: AnyObject {
    /// Seconds on a clock that only moves forward.
    var now: TimeInterval { get }
    func after(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> EqualiserTimer
    func every(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> EqualiserTimer
}

// MARK: - Live scheduler

@MainActor
final class MainEqualiserScheduler: EqualiserScheduling {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func after(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> EqualiserTimer {
        schedule(seconds, repeats: false, action)
    }

    func every(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> EqualiserTimer {
        schedule(seconds, repeats: true, action)
    }

    private func schedule(_ seconds: TimeInterval, repeats: Bool, _ action: @escaping @MainActor () -> Void) -> EqualiserTimer {
        let timer = Timer(timeInterval: seconds, repeats: repeats) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer.tolerance = min(0.1, seconds / 10)
        RunLoop.main.add(timer, forMode: .common)
        return EqualiserTimer { timer.invalidate() }
    }
}

// MARK: - Live claim

/// An exclusive `flock` on `equaliser.lock` in Zeus's Application Support folder. The lock dies with the process, so a
/// crash never leaves it held.
@MainActor
final class EqualiserFileClaim: EqualiserClaiming {
    private let url: URL
    private var descriptor: Int32 = -1

    init(url: URL = EqualiserFileClaim.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zeus/equaliser.lock")
    }

    func take() -> Bool {
        if descriptor >= 0 { return true }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let opened = open(url.path, O_CREAT | O_RDWR, 0o600)
        guard opened >= 0 else { return false }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            close(opened)
            return false
        }
        descriptor = opened
        return true
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}
