import Foundation

/// How the welcome guide is shown. Escape can fold the existing window into a small chip.
/// The step, choices and permission state stay with the guide. No second window is involved.
public struct OnboardingPresentation: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case expanded
        case minimized
    }

    public struct Progress: Equatable, Sendable {
        public var step: Int
        public var choices: [String]
        public var permissionState: [String]

        public init(step: Int, choices: [String], permissionState: [String]) {
            self.step = step
            self.choices = choices
            self.permissionState = permissionState
        }
    }

    public struct Size: Equatable, Sendable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    public enum Command: Equatable, Sendable {
        case escape
        case minimizeControl
        case reopen
    }

    public enum Effect: Equatable, Sendable {
        case resize(Size)
        case announce(String)
        case animated(Bool)
        case releaseKeyFocus
    }

    public static let expandedSize = Size(width: 960, height: 760)
    public static let minimizedSize = Size(width: 240, height: 44)
    /// The first appearance stays off the key window so typing elsewhere is left alone.
    public static let takesKeyFocusOnFirstShow = false

    public var phase: Phase
    public var progress: Progress
    public var reduceMotion: Bool

    public init(phase: Phase = .expanded, progress: Progress, reduceMotion: Bool) {
        self.phase = phase
        self.progress = progress
        self.reduceMotion = reduceMotion
    }

    /// Escape or the minimize control folds the guide. A second Escape leaves it folded.
    /// Reopen brings the same step back. Reduce Motion skips the resize animation.
    public mutating func send(_ command: Command) -> [Effect] {
        let motion = Effect.animated(!reduceMotion)
        switch (phase, command) {
        case (.expanded, .escape), (.expanded, .minimizeControl):
            phase = .minimized
            return [.resize(Self.minimizedSize), .announce("Setup minimized"), motion, .releaseKeyFocus]
        case (.minimized, .escape), (.minimized, .minimizeControl), (.expanded, .reopen):
            return []
        case (.minimized, .reopen):
            phase = .expanded
            return [.resize(Self.expandedSize), .announce("Setup restored"), motion]
        }
    }
}
