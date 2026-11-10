import CoreGraphics
import Foundation

/// L4 / O8 / O9: guided targets, AX snap, and click gating for walkthroughs.
public enum GuidedPresent {
    public struct ResolvedTarget: Equatable, Sendable {
        public var screenPoint: CGPoint
        public var label: String
        public var waitForClick: Bool
        public var hitRect: CGRect?

        public init(screenPoint: CGPoint, label: String, waitForClick: Bool, hitRect: CGRect? = nil) {
            self.screenPoint = screenPoint
            self.label = label
            self.waitForClick = waitForClick
            self.hitRect = hitRect
        }
    }

    public static func resolve(
        step: Walkthrough.Step,
        shots: [ScreenShot],
        snapshot: AXSnapshot?
    ) -> ResolvedTarget? {
        let mapper = PresentPointMapping.mapper(from: shots)
        let wait = step.waitForClick
        if let label = step.targetLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty,
           let snapshot,
           let element = snapshot.elements.first(where: { $0.label?.caseInsensitiveCompare(label) == .orderedSame })
            ?? snapshot.elements.first(where: { ($0.label ?? "").localizedCaseInsensitiveContains(label) }),
           let center = PresentPointMapping.screenCenter(of: element, mapper: mapper) {
            let rect = axHitRect(element: element, mapper: mapper)
            return ResolvedTarget(screenPoint: center, label: label, waitForClick: wait, hitRect: rect)
        }
        guard let target = step.target,
              let point = PresentPointMapping.screenPoint(x: target.x, y: target.y, screen: target.screen, in: shots) else {
            return nil
        }
        let shotIndex = (step.target?.screen ?? 1) - 1
        let shot = shots.indices.contains(shotIndex) ? shots[shotIndex] : shots[0]
        let tol = PresentPointMapping.ringTolerancePoints(for: shot)
        let rect = CGRect(x: point.x - tol, y: point.y - tol, width: tol * 2, height: tol * 2)
        return ResolvedTarget(
            screenPoint: point,
            label: step.target?.label ?? step.say,
            waitForClick: wait,
            hitRect: rect
        )
    }

    public static func clickHits(_ click: CGPoint, target: ResolvedTarget) -> Bool {
        if let rect = target.hitRect { return rect.contains(click) }
        return hypot(click.x - target.screenPoint.x, click.y - target.screenPoint.y) <= 60
    }

    private static func axHitRect(element: AXSnapshotElement, mapper: ScreenCoordinateMapper) -> CGRect? {
        let frame = element.frame
        let corners = [
            CGPoint(x: frame.minX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.maxY),
            CGPoint(x: frame.minX, y: frame.maxY),
        ]
        let mapped = corners.compactMap { mapper.convert($0, from: .ax, to: .screen, context: MapContext()) }
        guard mapped.count == 4 else { return nil }
        var rect = CGRect(origin: mapped[0], size: .zero)
        for p in mapped.dropFirst() { rect = rect.union(CGRect(origin: p, size: .zero)) }
        return rect.insetBy(dx: -4, dy: -4)
    }
}
