import Foundation

/// One timer for the part that is running. This type is not main-actor isolated.
///
/// A new arm replaces the previous timer. When the current timer fires and the part
/// is still unfinished, the record is the closed step `timedOut`, the restores that
/// are safe off the main thread, and exit code 70. The timer does not close a window
/// or a space: those end with the process. This value does not call `exit`.
public enum StepZeroWatchdog {
    public static let exitCode = 70

    public enum Step: String, Sendable, Equatable {
        case timedOut
    }

    public enum Restore: String, Sendable, Equatable, CaseIterable {
        case listeningMode
        case defaultOutput
        case stopChild
    }

    public struct Arm: Equatable, Sendable {
        public var generation: Int
        public var seconds: Int

        public init(generation: Int, seconds: Int) {
            self.generation = generation
            self.seconds = seconds
        }
    }

    public struct Fire: Equatable, Sendable {
        public var step: Step
        public var restores: [Restore]
        public var exitCode: Int
        public var closesWindow: Bool
        public var closesSpace: Bool

        public init(
            step: Step,
            restores: [Restore],
            exitCode: Int,
            closesWindow: Bool,
            closesSpace: Bool
        ) {
            self.step = step
            self.restores = restores
            self.exitCode = exitCode
            self.closesWindow = closesWindow
            self.closesSpace = closesSpace
        }
    }

    /// `seconds` below 1 does not arm a timer. Otherwise the generation moves forward by one.
    public static func arm(seconds: Int, after previous: Arm?) -> Arm? {
        guard seconds > 0 else { return nil }
        return Arm(generation: (previous?.generation ?? 0) + 1, seconds: seconds)
    }

    /// A generation that is not the current arm does not fire.
    public static func fire(generation: Int, current: Arm?) -> Fire? {
        guard let current, current.generation == generation else { return nil }
        return Fire(
            step: .timedOut,
            restores: Restore.allCases,
            exitCode: exitCode,
            closesWindow: false,
            closesSpace: false
        )
    }
}
