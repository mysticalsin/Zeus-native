import Foundation

/// When a keep-awake session should stop on its own: low battery, heat or time.
/// Pure, so the session, the Settings copy and the tests share one answer.
/// The battery and heat ideas come from Insomnia (MIT, Krish Garg); the logic is ours.
public struct KeepAwakeRules: Equatable, Sendable {
    /// Mirrors ProcessInfo.ThermalState without importing it here.
    public enum Thermal: Int, Comparable, Sendable {
        case nominal, fair, serious, critical
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    /// What the Mac reports right now.
    public struct Power: Equatable, Sendable {
        /// Nil on a Mac with no battery.
        public var batteryPercent: Int?
        public var isCharging: Bool
        public var onBattery: Bool
        public var thermal: Thermal

        public init(batteryPercent: Int? = nil, isCharging: Bool = false, onBattery: Bool = false, thermal: Thermal = .nominal) {
            self.batteryPercent = batteryPercent
            self.isCharging = isCharging
            self.onBattery = onBattery
            self.thermal = thermal
        }
    }

    public enum EndReason: Equatable, Sendable {
        case lowBattery(Int)
        case tooHot(Thermal)
        case timeUp

        /// Short line for Home and Settings ("Ended: battery 9%").
        public var text: String {
            switch self {
            case .lowBattery(let percent): "Ended: battery \(percent)%"
            case .tooHot: "Ended: Mac too hot"
            case .timeUp: "Ended: time up"
            }
        }
    }

    public enum Verdict: Equatable, Sendable {
        case keepGoing
        /// Keep going, and tell the person once: the battery reached the warning level.
        case warnLowBattery(Int)
        case end(EndReason)
    }

    /// Floors offered in Settings; 0 is Off.
    public static let floorChoices = [0, 5, 10, 15, 20]

    /// End below this battery percent while running on battery. 0 turns it off.
    public var batteryFloor: Int
    /// End once the thermal state reaches `hotLevel`.
    public var endWhenHot: Bool
    public var hotLevel: Thermal
    /// One notice at or below this percent on battery. 0 turns it off.
    public var warnAt: Int

    public init(batteryFloor: Int = 10, endWhenHot: Bool = true, hotLevel: Thermal = .critical, warnAt: Int = 20) {
        self.batteryFloor = batteryFloor
        self.endWhenHot = endWhenHot
        self.hotLevel = hotLevel
        self.warnAt = warnAt
    }

    /// `remaining` is nil for an open-ended session. `warned` is true once the notice was shown,
    /// so it fires once per session. Time up wins, then heat, then battery.
    public func evaluate(_ power: Power, elapsed: TimeInterval, remaining: TimeInterval?, warned: Bool) -> Verdict {
        if let remaining, remaining <= 0 { return .end(.timeUp) }
        if endWhenHot, power.thermal >= hotLevel { return .end(.tooHot(power.thermal)) }
        // Charging or on AC, the battery is not draining, so the floor and the notice wait.
        guard let percent = power.batteryPercent, power.onBattery, !power.isCharging else { return .keepGoing }
        if batteryFloor > 0, percent < batteryFloor { return .end(.lowBattery(percent)) }
        if warnAt > 0, percent <= warnAt, !warned { return .warnLowBattery(percent) }
        return .keepGoing
    }

    /// "Off", "10%": the Settings pop-up label for a floor.
    public static func floorLabel(_ percent: Int) -> String { percent <= 0 ? "Off" : "\(percent)%" }

    /// The floor for a pop-up label; anything unknown is Off.
    public static func floor(fromLabel label: String) -> Int {
        floorChoices.first { floorLabel($0) == label } ?? 0
    }
}

/// Session lengths offered in Home and Settings. Nil minutes is open-ended.
public enum KeepAwakeLength {
    public static let short = [15, 30, 60, 120]
    public static let long = [4 * 60, 8 * 60, 24 * 60]
    public static let all: [Int?] = short.map(Optional.some) + long.map(Optional.some) + [nil]

    /// "15 minutes", "1 hour", "2 hours", "Indefinitely".
    public static func label(_ minutes: Int?) -> String {
        guard let minutes else { return "Indefinitely" }
        guard minutes >= 60, minutes % 60 == 0 else { return "\(minutes) minutes" }
        return minutes == 60 ? "1 hour" : "\(minutes / 60) hours"
    }

    public static func minutes(fromLabel label: String) -> Int?? {
        all.first { Self.label($0) == label }
    }

    /// Countdown text: "9:05" under an hour, "3:59:05" above, "On" open-ended.
    public static func countdown(_ remaining: TimeInterval?) -> String {
        guard let remaining else { return "On" }
        let total = max(0, Int(remaining))
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
