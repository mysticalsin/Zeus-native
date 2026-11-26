import Foundation

/// A type step or a wait step shows the next control before that step is finished.
/// The preview stays until a click lands in that rectangle, or until the idle budget
/// cancels it. The clock never finishes the step.
public struct GuidePreview: Equatable, Sendable {
    /// An unused preview is cancelled after this many seconds. The caller passes the clock in.
    public static let idleBudget: TimeInterval = 45

    public enum Kind: String, Equatable, Sendable {
        case click
        case type
        case wait
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case preview
        case advanced
        case cancelled
    }

    /// What one event did. `.advanced` is the only finish, and only a click can return it.
    public enum Mark: Equatable, Sendable {
        case waiting
        case revealed
        case stayed
        case advanced
        case cancelled
    }

    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        public var isUsable: Bool { x.isFinite && y.isFinite }
    }

    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        /// A real rectangle. A negative origin is a display to the left of the primary.
        public var isDrawable: Bool {
            x.isFinite && y.isFinite && width.isFinite && height.isFinite && width > 0 && height > 0
        }

        /// The minimum edges are inside. The far edges are outside.
        public func contains(_ point: Point) -> Bool {
            guard isDrawable, point.isUsable else { return false }
            return point.x >= x && point.x < x + width && point.y >= y && point.y < y + height
        }
    }

    public private(set) var phase: Phase = .idle
    public private(set) var kind: Kind?
    public private(set) var rect: Rect?
    public private(set) var revealedAt: TimeInterval?

    public init() {}

    /// Show the next control when that step is a type or a wait.
    /// A click step, a flat rectangle, or a clock that is not finite leaves the preview idle.
    @discardableResult
    public mutating func reveal(_ kind: Kind, rect: Rect, at now: TimeInterval) -> Mark {
        guard phase == .idle else { return .waiting }
        guard kind == .type || kind == .wait else { return .waiting }
        guard now.isFinite, rect.isDrawable else { return .waiting }
        self.kind = kind
        self.rect = rect
        self.revealedAt = now
        phase = .preview
        return .revealed
    }

    /// A click inside the preview rectangle finishes the step, before the idle budget.
    /// A click once the budget has elapsed cancels the preview and does not finish it.
    @discardableResult
    public mutating func click(_ point: Point, at now: TimeInterval) -> Mark {
        guard phase == .preview, let start = revealedAt, let rect else { return .waiting }
        guard now.isFinite, now >= start else { return .stayed }
        if now - start >= Self.idleBudget { return cancel() }
        guard point.isUsable, rect.contains(point) else { return .stayed }
        phase = .advanced
        return .advanced
    }

    /// Move the injected clock. Time can cancel an unused preview. It cannot finish the step.
    @discardableResult
    public mutating func tick(at now: TimeInterval) -> Mark {
        guard phase == .preview, let start = revealedAt else { return .waiting }
        guard now.isFinite, now >= start else { return .stayed }
        if now - start >= Self.idleBudget { return cancel() }
        return .stayed
    }

    private mutating func cancel() -> Mark {
        phase = .cancelled
        return .cancelled
    }
}
