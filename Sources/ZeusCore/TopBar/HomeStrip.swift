import Foundation

/// What the slim strip under Home's cards shows, and only when it matters: the Mac is on battery,
/// the charge is low, or a keep-awake session is running (or just ended for a reason worth saying).
public struct HomeStrip: Equatable, Sendable {
    public enum Chip: Equatable, Sendable {
        case battery(level: Int, charging: Bool, low: Bool)
        case keepAwake(label: String, openEnded: Bool)
        case keepAwakeEnded(String)
    }

    public static let lowLevel = 20
    public static let height: CGFloat = 30
    /// Gap between the cards and the strip.
    public static let gap: CGFloat = 8

    public var chips: [Chip]

    public var isVisible: Bool { !chips.isEmpty }
    /// Extra panel height the strip takes on Home.
    public var extraHeight: CGFloat { isVisible ? Self.height + Self.gap : 0 }

    public init(chips: [Chip]) { self.chips = chips }

    /// `battery` nil means a desktop Mac. A charger with a full battery shows nothing.
    public static func make(batteryLevel: Int?, charging: Bool, pluggedIn: Bool, keepAwakeActive: Bool, keepAwakeLabel: String,
                            keepAwakeOpenEnded: Bool, keepAwakeEndedText: String?) -> HomeStrip {
        var chips: [Chip] = []
        if let level = batteryLevel {
            let low = level <= lowLevel && !pluggedIn
            if low || charging || !pluggedIn {
                chips.append(.battery(level: level, charging: charging, low: low))
            }
        }
        if keepAwakeActive {
            chips.append(.keepAwake(label: keepAwakeLabel, openEnded: keepAwakeOpenEnded))
        } else if let text = keepAwakeEndedText {
            chips.append(.keepAwakeEnded(text))
        }
        return HomeStrip(chips: chips)
    }
}
