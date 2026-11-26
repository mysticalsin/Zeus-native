import Foundation

/// When a keep-awake session should stop on its own: low battery, heat or time.
/// Pure, so the session, the Settings copy and the tests share one answer.
/// The battery and heat ideas come from Insomnia (MIT, Krish Garg); the logic is ours.
public struct KeepAwakeRules: Equatable, Sendable {
    /// Mirrors ProcessInfo.ThermalState. The rank lives in `KeepAwakeRulesBox`.
    public typealias Thermal = KeepAwakeRulesBox.Thermal

    /// What the Mac reports right now.
    public typealias Power = KeepAwakeRulesBox.Power

    public typealias EndReason = KeepAwakeRulesBox.EndReason

    public typealias Verdict = KeepAwakeRulesBox.Verdict

    /// Floors offered in Settings; 0 is Off.
    public static let floorChoices = KeepAwakeRulesBox.floorChoices

    /// End below this battery percent while running on battery. 0 turns it off.
    public var batteryFloor: Int
    /// End once the thermal state reaches `hotLevel`.
    public var endWhenHot: Bool
    public var hotLevel: Thermal
    /// One notice at or below this percent on battery. 0 turns it off.
    public var warnAt: Int

    public init(batteryFloor: Int = KeepAwakeRulesBox.defaultBatteryFloor,
                endWhenHot: Bool = KeepAwakeRulesBox.defaultEndWhenHot,
                hotLevel: Thermal = KeepAwakeRulesBox.defaultHotLevel,
                warnAt: Int = KeepAwakeRulesBox.defaultWarnAt) {
        self.batteryFloor = batteryFloor
        self.endWhenHot = endWhenHot
        self.hotLevel = hotLevel
        self.warnAt = warnAt
    }

    /// `remaining` is nil for an open-ended session. `warned` is true once the notice was shown,
    /// so it fires once per session. Time up wins, then heat, then battery.
    public func evaluate(_ power: Power, elapsed: TimeInterval, remaining: TimeInterval?, warned: Bool) -> Verdict {
        KeepAwakeRulesBox.evaluate(batteryFloor: batteryFloor, endWhenHot: endWhenHot, hotLevel: hotLevel,
                                   warnAt: warnAt, power: power, elapsed: elapsed, remaining: remaining, warned: warned)
    }

    /// "Off", "10%": the Settings pop-up label for a floor.
    public static func floorLabel(_ percent: Int) -> String { KeepAwakeRulesBox.floorLabel(percent) }

    /// The floor for a pop-up label; anything unknown is Off.
    public static func floor(fromLabel label: String) -> Int { KeepAwakeRulesBox.floor(fromLabel: label) }
}

#if os(macOS)
extension KeepAwakeRules.Thermal {
    /// The one mapping from the system's state, shared by Keep Awake and Diagnostics.
    /// Linux Foundation has no thermal state, so this mapping stays on the Mac.
    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }
}
#endif

/// Session lengths offered in Home and Settings. Nil minutes is open-ended.
public enum KeepAwakeLength {
    public static let short = KeepAwakeRulesBox.shortLengths
    public static let long = KeepAwakeRulesBox.longLengths
    public static let all: [Int?] = KeepAwakeRulesBox.allLengths

    /// "15 minutes", "1 hour", "2 hours", "Indefinitely".
    public static func label(_ minutes: Int?) -> String { KeepAwakeRulesBox.lengthLabel(minutes) }

    public static func minutes(fromLabel label: String) -> Int?? { KeepAwakeRulesBox.minutes(fromLabel: label) }

    /// Countdown text: "9:05" under an hour, "3:59:05" above, "On" open-ended.
    public static func countdown(_ remaining: TimeInterval?) -> String { KeepAwakeRulesBox.countdown(remaining) }
}
