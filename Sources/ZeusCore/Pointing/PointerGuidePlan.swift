import Foundation

/// One step of the on-screen pointer guide: Zeus's bolt, the ring around the control, and the caption.
public struct PointerGuideStep: Equatable, Sendable, Codable {
    public var id: String
    public var bolt: PointerGuidePoint
    public var ring: PointerGuideRect
    public var caption: String

    public init(id: String, bolt: PointerGuidePoint, ring: PointerGuideRect, caption: String) {
        self.id = id
        self.bolt = bolt
        self.ring = ring
        self.caption = caption
    }

    public var boltPoint: CGPoint { CGPoint(x: bolt.x, y: bolt.y) }
    public var ringRect: CGRect { CGRect(x: ring.x, y: ring.y, width: ring.width, height: ring.height) }
}

public struct PointerGuidePoint: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

public struct PointerGuideRect: Equatable, Sendable, Codable {
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

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    public func contains(_ point: PointerGuidePoint) -> Bool {
        cgRect.contains(point.cgPoint)
    }

    public var center: PointerGuidePoint {
        PointerGuidePoint(x: x + width / 2, y: y + height / 2)
    }
}

/// What a click on the guide did. Every case stays on this device.
public enum PointerGuideAdvance: Equatable, Sendable {
    /// The next step is ready.
    case step(PointerGuideStep)
    /// The last step is done.
    case finished
    /// The click missed the ring. The current step stays.
    case waiting
}

/// The bolt, ring and caption for one moment of a step. Flight and caption use Zeus's own motion types.
public struct PointerGuidePose: Equatable, Sendable {
    public var bolt: CGPoint
    public var ring: CGRect
    public var caption: String
    public var visibleCaption: String
    public var flight: CompanionFlight
}

/// One ring the live overlay already resolved, turned into a guide plan.
public enum PointerGuideAdmission {
    public static func step(id: String, bolt: CGPoint, ring: CGRect, caption: String, reduceMotion: Bool) -> PointerGuidePlan? {
        let line = caption.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        guard (1...PointerGuidePlan.maxCaption).contains(line.count) else { return nil }
        guard ring.width > 0, ring.height > 0, bolt.x.isFinite, bolt.y.isFinite else { return nil }
        let safeID = id.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil ? id : "step"
        let step = PointerGuideStep(
            id: safeID,
            bolt: PointerGuidePoint(x: bolt.x, y: bolt.y),
            ring: PointerGuideRect(x: ring.minX, y: ring.minY, width: ring.width, height: ring.height),
            caption: line)
        return PointerGuidePlan(steps: [step], reduceMotion: reduceMotion)
    }
}

/// The steps from one model reply. Clicks move through them on device.
public struct PointerGuidePlan: Equatable, Sendable {
    public static let captionCharacterDelay: TimeInterval = 0.04
    public static let maxSteps = 8
    public static let maxCaption = 40

    public private(set) var steps: [PointerGuideStep]
    public private(set) var index: Int
    public let reduceMotion: Bool
    /// One admission is one model turn. Clicks do not add to this.
    public private(set) var modelTurns: Int

    public init?(steps: [PointerGuideStep], reduceMotion: Bool) {
        guard Self.valid(steps) else { return nil }
        self.steps = steps
        self.index = 0
        self.reduceMotion = reduceMotion
        self.modelTurns = 1
    }

    public var current: PointerGuideStep? {
        steps.indices.contains(index) ? steps[index] : nil
    }

    /// Bolt, ring and caption at `now`. Reduce Motion settles the bolt, shows the ring, and shows the whole caption.
    public func pose(from origin: CGPoint, at now: TimeInterval, beganAt: TimeInterval, reduceMotion live: Bool) -> PointerGuidePose? {
        guard let step = current else { return nil }
        let reduced = live || reduceMotion
        let flight = CompanionFlight.plan(from: origin, to: step.boltPoint, reducedMotion: reduced)
        var label = CompanionPointingLabel(text: step.caption, beganAt: beganAt, reduceMotion: reduced)
        if !reduced {
            var ticks = 0
            while !label.isComplete, label.nextCharacterAt <= now, ticks < step.caption.count {
                let due = label.nextCharacterAt
                label.advance(at: due, reduceMotion: false, characterDelay: Self.captionCharacterDelay)
                ticks += 1
                if label.nextCharacterAt <= due { break }
            }
        }
        let elapsed = max(0, now - beganAt)
        return PointerGuidePose(
            bolt: flight.sample(at: elapsed).position,
            ring: step.ringRect,
            caption: step.caption,
            visibleCaption: label.visibleText,
            flight: flight
        )
    }

    /// A click inside the current ring moves to the next step. A miss stays put.
    public mutating func click(at point: PointerGuidePoint) -> PointerGuideAdvance {
        guard let step = current else { return .finished }
        guard step.ring.contains(point) else { return .waiting }
        return confirmCurrentStep()
    }

    /// The hit is already known to be inside the current ring.
    public mutating func confirmCurrentStep() -> PointerGuideAdvance {
        guard current != nil else { return .finished }
        index += 1
        if let next = current { return .step(next) }
        return .finished
    }

    private static func valid(_ steps: [PointerGuideStep]) -> Bool {
        guard (1...maxSteps).contains(steps.count) else { return false }
        var seen = Set<String>()
        for step in steps {
            guard step.id.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil else { return false }
            guard seen.insert(step.id).inserted else { return false }
            guard (1...maxCaption).contains(step.caption.count) else { return false }
            guard step.bolt.x.isFinite, step.bolt.y.isFinite else { return false }
            guard step.ring.width > 0, step.ring.height > 0,
                  step.ring.x.isFinite, step.ring.y.isFinite,
                  step.ring.width.isFinite, step.ring.height.isFinite else { return false }
        }
        return true
    }
}
