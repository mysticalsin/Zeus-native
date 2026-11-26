import Foundation

/// Battery, heat, and time rules for a keep-awake session, plus the floor labels,
/// the length labels, and the countdown text.
/// The caller supplies the power sample, how long the session has already run, and the time remaining.
/// Elapsed time is accepted so the session and this box share one signature. It does not change the verdict.
/// This type does not read a screen, a pointer, a clock, or a stored setting.
public enum KeepAwakeRulesBox {
    public enum Thermal: Int, Comparable, Sendable {
        case nominal = 0, fair, serious, critical
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

    public static let defaultBatteryFloor = 10
    public static let defaultEndWhenHot = true
    public static let defaultHotLevel = Thermal.critical
    public static let defaultWarnAt = 20

    /// Floors offered in Settings. 0 is Off.
    public static let floorChoices = [0, 5, 10, 15, 20]

    /// Session lengths offered in Home and Settings, in minutes. Nil is open-ended.
    public static let shortLengths = [15, 30, 60, 120]
    public static let longLengths = [4 * 60, 8 * 60, 24 * 60]
    public static let allLengths: [Int?] = shortLengths.map(Optional.some) + longLengths.map(Optional.some) + [nil]

    /// `remaining` nil is an open-ended session. `warned` is true once the notice was shown,
    /// so it fires once per session. Time up wins, then heat, then battery.
    /// Charging or on AC, the battery is not draining, so the floor and the notice wait.
    public static func evaluate(batteryFloor: Int, endWhenHot: Bool, hotLevel: Thermal, warnAt: Int,
                                power: Power, elapsed: TimeInterval, remaining: TimeInterval?, warned: Bool) -> Verdict {
        if let remaining, remaining <= 0 { return .end(.timeUp) }
        if endWhenHot, power.thermal >= hotLevel { return .end(.tooHot(power.thermal)) }
        guard let percent = power.batteryPercent, power.onBattery, !power.isCharging else { return .keepGoing }
        if batteryFloor > 0, percent < batteryFloor { return .end(.lowBattery(percent)) }
        if warnAt > 0, percent <= warnAt, !warned { return .warnLowBattery(percent) }
        return .keepGoing
    }

    /// "Off", "10%": the Settings pop-up label for a floor.
    public static func floorLabel(_ percent: Int) -> String { percent <= 0 ? "Off" : "\(percent)%" }

    /// The floor for a pop-up label. Anything unknown is Off.
    public static func floor(fromLabel label: String) -> Int {
        floorChoices.first { floorLabel($0) == label } ?? 0
    }

    /// "15 minutes", "1 hour", "2 hours", "Indefinitely".
    public static func lengthLabel(_ minutes: Int?) -> String {
        guard let minutes else { return "Indefinitely" }
        guard minutes >= 60, minutes % 60 == 0 else { return "\(minutes) minutes" }
        return minutes == 60 ? "1 hour" : "\(minutes / 60) hours"
    }

    /// The minutes for a length label. `.some(nil)` is Indefinitely. `nil` is not a preset.
    public static func minutes(fromLabel label: String) -> Int?? {
        allLengths.first { lengthLabel($0) == label }
    }

    /// Countdown text: "9:05" under an hour, "3:59:05" above, "On" when open-ended.
    /// A fraction of a second is dropped. A negative remainder is shown as zero.
    public static func countdown(_ remaining: TimeInterval?) -> String {
        guard let remaining else { return "On" }
        let total = max(0, Int(remaining))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
}
