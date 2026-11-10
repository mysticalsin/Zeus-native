import Foundation

/// `[ACTION:{"type":"mac.walkthrough",...}]`: ZEUS teaches instead of doing. Each step points at
/// something and says what to do; it moves on when you click there (or say "next").
public struct Walkthrough: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public var say: String
        public var target: PointTarget?
        /// Accessibility label to snap the ring to (preferred over raw x/y).
        public var targetLabel: String?
        /// When true, the tour waits for a click on the target before "next" advances it.
        public var waitForClick: Bool

        public init(say: String, target: PointTarget? = nil, targetLabel: String? = nil, waitForClick: Bool = false) {
            self.say = say
            self.target = target
            self.targetLabel = targetLabel
            self.waitForClick = waitForClick
        }
    }

    public static let maxSteps = 15

    public var title: String
    public var steps: [Step]

    public init(title: String, steps: [Step]) {
        self.title = title
        self.steps = steps
    }

    public static func parse(_ payload: [String: JSONValue]) -> Walkthrough? {
        guard let raw = payload["steps"]?.arrayValue, !raw.isEmpty, raw.count <= maxSteps else { return nil }
        let steps = raw.compactMap { item -> Step? in
            guard let say = item["say"]?.stringValue, !say.isEmpty else { return nil }
            var target: PointTarget?
            var screen: Int?
            if let value = item["screen"] {
                guard let parsed = MacActionNumbers.screen(value) else { return nil }
                screen = parsed
            }
            if item["x"] != nil || item["y"] != nil {
                guard let rawX = item["x"], let rawY = item["y"],
                      let x = MacActionNumbers.integer(rawX), let y = MacActionNumbers.integer(rawY) else { return nil }
                target = PointTarget(x: x, y: y, label: item["label"]?.stringValue, screen: screen)
            }
            let label = item["target"]?.stringValue ?? item["label"]?.stringValue
            let wait = item["wait"]?.boolValue ?? item["waitForClick"]?.boolValue ?? (target != nil)
            return Step(say: say, target: target, targetLabel: label, waitForClick: wait)
        }
        guard steps.count == raw.count else { return nil }
        return Walkthrough(title: payload["title"]?.stringValue ?? "", steps: steps)
    }
}

/// Where you are in a walkthrough. Pure state, driven by clicks, voice and Esc.
public struct WalkthroughSession: Equatable, Sendable {
    public enum State: Equatable, Sendable { case running, finished, cancelled }

    public let walkthrough: Walkthrough
    public private(set) var index = 0
    public private(set) var state: State = .running
    /// Delayed clicks and timers belong to this exact presentation, including after going back.
    public private(set) var revision = UUID()

    public init(_ walkthrough: Walkthrough) {
        self.walkthrough = walkthrough
        if walkthrough.steps.isEmpty { state = .finished }
    }

    public var current: Walkthrough.Step? { state == .running ? walkthrough.steps[index] : nil }
    public var progress: String { "Step \(index + 1) of \(walkthrough.steps.count)" }

    public mutating func next() {
        guard state == .running else { return }
        revision = UUID()
        if index + 1 < walkthrough.steps.count { index += 1 } else { state = .finished }
    }

    /// An old click/timer can never advance a replacement tour or the next step twice.
    @discardableResult
    public mutating func next(ifRevision expected: UUID) -> Bool {
        guard state == .running, revision == expected else { return false }
        next()
        return true
    }

    public mutating func back() {
        guard state == .running, index > 0 else { return }
        revision = UUID()
        index -= 1
    }

    public mutating func cancel() {
        if state == .running { state = .cancelled; revision = UUID() }
    }

    /// Spoken words that move the tour along.
    public static func command(for transcript: String) -> String? {
        let t = transcript.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        if ["next", "done", "ok next", "got it", "okay", "ok"].contains(t) { return "next" }
        if ["back", "go back", "previous"].contains(t) { return "back" }
        if ["stop", "cancel", "stop the tour", "end tour"].contains(t) { return "cancel" }
        return nil
    }
}
