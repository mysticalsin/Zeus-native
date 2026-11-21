import CoreGraphics
import Foundation

/// Click-gated steps for a guided tour.
///
/// The production Esc monitor stays in WalkthroughController and runs only when the existing
/// Accessibility grant is already on. This type adds no prompt and no Input Monitoring.
/// It does not sleep. A click is decided when it arrives.
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

    /// More than `Walkthrough.maxSteps` (15) is refused, so step 16 never starts.
    public init?(steps: [Step]) {
        guard !steps.isEmpty, steps.count <= Walkthrough.maxSteps else { return nil }
        self.steps = steps
        self.index = 0
        self.target = steps[0].target
        self.cancelled = false
    }

    /// A click outside the target stays on this step. A click inside advances.
    /// Hit testing is `GuidedPresent.clickHits`.
    public mutating func click(at point: CGPoint) {
        guard !cancelled, let current = target else { return }
        guard GuidedPresent.clickHits(point, target: current) else { return }
        guard index + 1 < steps.count else {
            target = nil
            return
        }
        index += 1
        target = steps[index].target
    }

    public mutating func cancel() {
        cancelled = true
        target = nil
    }
}
