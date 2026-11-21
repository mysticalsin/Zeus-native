import CoreGraphics
import Foundation

/// Click-gated steps for a guided tour.
///
/// The production Esc monitor stays in WalkthroughController and runs only when the existing
/// Accessibility grant is already on. This type adds no prompt and no Input Monitoring.
/// It does not sleep. A click is decided when it arrives, against the rect last supplied for that step.
public struct GuidedSteps: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public var say: String
        public var target: GuidedPresent.ResolvedTarget

        public init(say: String, target: GuidedPresent.ResolvedTarget) {
            self.say = say
            self.target = target
        }
    }

    public static let dragThreshold: CGFloat = 8

    public private(set) var steps: [Step]
    public private(set) var index: Int
    public private(set) var target: GuidedPresent.ResolvedTarget?
    public private(set) var cancelled: Bool
    private var liveRects: [Int: CGRect] = [:]

    public var progress: String { "Step \(index + 1) of \(steps.count)" }

    public var accessibilityLabel: String {
        let name = target?.label ?? (steps.indices.contains(index) ? steps[index].say : "")
        return "\(progress), \(name)"
    }

    /// More than `Walkthrough.maxSteps` (15) is refused, so step 16 never starts.
    public init?(steps: [Step]) {
        guard !steps.isEmpty, steps.count <= Walkthrough.maxSteps else { return nil }
        self.steps = steps
        self.index = 0
        self.target = steps[0].target
        self.cancelled = false
    }

    public mutating func click(at point: CGPoint) {
        click(at: point, count: 1, pressedAt: point)
    }

    /// One call advances one step. A count above 1 does not skip. A drag past `dragThreshold` stays put.
    /// The hit rect is the one last set for this step, not the rect from init.
    public mutating func click(at point: CGPoint, count: Int, pressedAt: CGPoint) {
        guard count >= 1, !cancelled else { return }
        if hypot(point.x - pressedAt.x, point.y - pressedAt.y) > Self.dragThreshold { return }
        guard let current = currentTarget() else { return }
        guard GuidedPresent.clickHits(point, target: current) else { return }
        guard index + 1 < steps.count else {
            target = nil
            return
        }
        index += 1
        target = currentTarget()
    }

    public mutating func setRect(_ rect: CGRect, forStep step: Int, label: String? = nil) {
        guard steps.indices.contains(step) else { return }
        liveRects[step] = rect
        if let label { steps[step].target.label = label }
        if index == step, !cancelled { target = currentTarget() }
    }

    public mutating func move(to newIndex: Int) {
        guard steps.indices.contains(newIndex) else { return }
        index = newIndex
        cancelled = false
        target = currentTarget()
    }

    public mutating func cancel() {
        cancelled = true
        target = nil
    }

    private func currentTarget() -> GuidedPresent.ResolvedTarget? {
        guard steps.indices.contains(index) else { return nil }
        var step = steps[index].target
        if let rect = liveRects[index] {
            step.hitRect = rect
            step.screenPoint = CGPoint(x: rect.midX, y: rect.midY)
        }
        return step
    }
}
