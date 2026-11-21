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

    /// Red stub: every press advances two steps, hit testing included.
    public mutating func click(at point: CGPoint) {
        _ = point
        guard !cancelled else { return }
        guard index + 2 < steps.count else {
            target = nil
            return
        }
        index += 2
        target = steps[index].target
    }

    public static let dragThreshold: CGFloat = 8

    /// Red stub: ignores the drag, repeats the click for every count, and keeps the rect from init.
    public mutating func click(at point: CGPoint, count: Int, pressedAt: CGPoint) {
        _ = pressedAt
        let times = max(count, 1)
        for _ in 0..<times { click(at: point) }
    }

    public mutating func setRect(_ rect: CGRect, forStep step: Int, label: String? = nil) {
        _ = (rect, step, label)
    }

    public var accessibilityLabel: String { progress }

    public mutating func move(to newIndex: Int) {
        guard steps.indices.contains(newIndex) else { return }
        index = newIndex
        target = steps[newIndex].target
    }

    public mutating func cancel() {
        cancelled = true
        target = nil
    }
}
