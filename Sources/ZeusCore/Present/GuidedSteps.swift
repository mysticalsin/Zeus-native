import CoreGraphics
import Foundation

/// Click-gated steps.
///
/// The production Esc monitor stays in WalkthroughController and runs only when the existing
/// Accessibility grant is already on. This type adds no prompt and no Input Monitoring.
/// It does not sleep.
public struct GuidedSteps: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public var say: String
        public var target: GuidedPresent.ResolvedTarget

        public init(say: String, target: GuidedPresent.ResolvedTarget) {
            self.say = say
            self.target = target
        }
    }

    public private(set) var steps: [Step]
    public private(set) var index: Int
    public private(set) var target: GuidedPresent.ResolvedTarget?
    public private(set) var cancelled: Bool

    public var progress: String { "Step \(index + 1) of \(steps.count)" }

    public init?(steps: [Step]) {
        guard !steps.isEmpty else { return nil }
        self.steps = steps
        self.index = 0
        self.target = steps[0].target
        self.cancelled = false
    }

    public mutating func click(at point: CGPoint) {
        guard index + 1 < steps.count else { return }
        index += 1
        target = steps[index].target
        _ = point
    }

    public mutating func cancel() {
        cancelled = true
    }
}
