/// Battery numbers for one earbuds device.
/// A part counts only from 1 to 100. Zero, a gap, and anything above 100 are
/// no reading, so a missing part is never drawn as zero.
public enum EarbudsPart: Hashable, Sendable, CaseIterable {
    case left
    case right
    case `case`
    case single
}

public enum BatteryLevel: Hashable, Sendable {
    case unknown
    case fresh(Int)
    case lastKnown(Int)
}

public enum BatteryReading {
    /// 1 to 100 passes. Nil, zero, negatives, and anything above 100 do not.
    public static func valid(_ raw: Int?) -> Int? {
        guard let raw, (1 ... 100).contains(raw) else { return nil }
        return raw
    }
}

public enum EarbudsParts {
    /// Left or right answers: left, right, and the case. Otherwise a single
    /// answer stands alone. Anything else has no battery row.
    public static func layout(answering: Set<EarbudsPart>) -> [EarbudsPart] {
        if answering.contains(.left) || answering.contains(.right) {
            return [.left, .right, .case]
        }
        if answering.contains(.single) {
            return [.single]
        }
        return []
    }
}

public struct BatteryBook: Equatable, Sendable {
    public static let lastKnownLifetime: Double = 1800

    private struct Stamp: Equatable, Sendable {
        var value: Int
        var at: Double
    }

    private var memory: [EarbudsPart: Stamp] = [:]

    public init() {}

    /// A valid part replaces its memory and stamps `now`. An invalid part
    /// changes nothing, so the previous value stays.
    public mutating func merge(_ raw: [EarbudsPart: Int?], now: Double) {
        for (part, value) in raw {
            guard let valid = BatteryReading.valid(value) else { continue }
            memory[part] = Stamp(value: valid, at: now)
        }
    }

    /// No memory is unknown. The instant of the read is fresh. Older than
    /// that, and still inside 1800 seconds, is last known. At 1800 seconds
    /// it is unknown again.
    public func level(_ part: EarbudsPart, now: Double) -> BatteryLevel {
        guard let stamp = memory[part] else { return .unknown }
        let age = now - stamp.at
        if age <= 0 { return .fresh(stamp.value) }
        if age < Self.lastKnownLifetime { return .lastKnown(stamp.value) }
        return .unknown
    }

    public func hasAnyFresh(now: Double) -> Bool {
        memory.keys.contains { part in
            if case .fresh = level(part, now: now) { return true }
            return false
        }
    }
}
