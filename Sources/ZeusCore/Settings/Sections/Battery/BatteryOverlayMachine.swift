import Foundation

/// How the charge overlay is drawn. The gauge is the outline Zeus already flashes.
public enum BatteryOverlayStyle: String, CaseIterable, Equatable, Sendable {
    case gauge
    case ring
    case readout

    public static let storageKey = "battery.overlayStyle"
    public static let `default` = BatteryOverlayStyle.gauge

    public var title: String {
        switch self {
        case .gauge: "Gauge"
        case .ring: "Ring"
        case .readout: "Readout"
        }
    }

    public var helper: String {
        switch self {
        case .gauge: "A green outline fills with the charge."
        case .ring: "A ring fills with the charge."
        case .readout: "The percent is shown on its own."
        }
    }

    public var accessibilityLabel: String { "\(title). \(helper)" }

    /// An unknown stored value stays on the gauge.
    public static func resolve(_ stored: String) -> BatteryOverlayStyle {
        BatteryOverlayStyle(rawValue: stored) ?? .gauge
    }
}

/// The existing `lights.battery` switch. Default on, same key as the catalog.
public enum BatteryLightsSetting {
    public static let key = "lights.battery"
    public static let defaultEnabled = true
}

public enum BatteryMotion {
    public static let overlayDuration: TimeInterval = 0.22

    public static func duration(reduceMotion: Bool, style: BatteryOverlayStyle = .gauge) -> TimeInterval {
        _ = style
        return reduceMotion ? 0 : overlayDuration
    }
}

public struct BatteryPowerSample: Equatable, Sendable {
    public var percent: Int?
    public var charging: Bool
    public var onAC: Bool

    public init(percent: Int?, charging: Bool, onAC: Bool) {
        self.percent = percent
        self.charging = charging
        self.onAC = onAC
    }
}

public enum BatteryOverlayTrigger: Equatable, Sendable {
    case chargerConnected
    case chargerDisconnected
    case lowBattery
}

public struct BatteryOverlayShow: Equatable, Sendable {
    public var trigger: BatteryOverlayTrigger
    public var style: BatteryOverlayStyle
    public var percent: Int
    public var charging: Bool
    public var until: TimeInterval
    public var animationDuration: TimeInterval
    public var accessibilityLabel: String

    public init(trigger: BatteryOverlayTrigger, style: BatteryOverlayStyle, percent: Int, charging: Bool, until: TimeInterval, animationDuration: TimeInterval, accessibilityLabel: String) {
        self.trigger = trigger
        self.style = style
        self.percent = percent
        self.charging = charging
        self.until = until
        self.animationDuration = animationDuration
        self.accessibilityLabel = accessibilityLabel
    }
}

public enum BatteryOverlayPhase: Equatable, Sendable {
    case idle
    case showing(BatteryOverlayShow)
    case cooldown(until: TimeInterval)
}

/// Idle, showing, then cooldown. A charger edge or a low reading is the only way in,
/// and only while `lights.battery` is on. The first reading seeds the machine.
public struct BatteryOverlayMachine: Equatable, Sendable {
    public static let showDuration: TimeInterval = 2.2
    public static let cooldownDuration: TimeInterval = 8
    public static let lowBatteryAt = 10

    public var phase: BatteryOverlayPhase
    public var style: BatteryOverlayStyle
    public var lightsEnabled: Bool
    public var reduceMotion: Bool
    public var seeded: Bool
    public var lastSample: BatteryPowerSample?
    public var lastLowPercent: Int?

    public init(style: BatteryOverlayStyle = .gauge, lightsEnabled: Bool = true, reduceMotion: Bool = false) {
        phase = .idle
        self.style = style
        self.lightsEnabled = lightsEnabled
        self.reduceMotion = reduceMotion
        seeded = false
        lastSample = nil
        lastLowPercent = nil
    }

    public enum Event: Equatable, Sendable {
        case power(BatteryPowerSample, at: TimeInterval)
        case advance(to: TimeInterval)
        case setLights(Bool)
        case setStyle(BatteryOverlayStyle)
        case setReduceMotion(Bool)
    }

    public enum Effect: Equatable, Sendable {
        case present(BatteryOverlayShow)
        case dismiss
    }

    public static func reduce(_ state: BatteryOverlayMachine, _ event: Event) -> (BatteryOverlayMachine, [Effect]) {
        var state = state
        switch event {
        case .setLights(let on):
            state.lightsEnabled = on
            guard !on, case .showing = state.phase else { return (state, []) }
            state.phase = .idle
            return (state, [.dismiss])
        case .setStyle(let style):
            state.style = style
            return (state, [])
        case .setReduceMotion(let on):
            state.reduceMotion = on
            return (state, [])
        case .advance(let time):
            switch state.phase {
            case .showing(let show) where time >= show.until:
                state.phase = .cooldown(until: time + cooldownDuration)
                return (state, [.dismiss])
            case .cooldown(let until) where time >= until:
                state.phase = .idle
                return (state, [])
            default:
                return (state, [])
            }
        case .power(let sample, let at):
            return receive(state, sample, at: at)
        }
    }

    private static func receive(_ state: BatteryOverlayMachine, _ sample: BatteryPowerSample, at: TimeInterval) -> (BatteryOverlayMachine, [Effect]) {
        var state = state
        guard let percent = sample.percent, (0...100).contains(percent) else { return (state, []) }
        let previous = state.lastSample
        state.lastSample = sample
        state.seeded = true
        guard state.lightsEnabled else {
            if case .showing = state.phase {
                state.phase = .idle
                return (state, [.dismiss])
            }
            return (state, [])
        }
        if case .cooldown = state.phase { return (state, []) }
        let trigger = trigger(previous: previous, sample: sample, percent: percent, lastLow: state.lastLowPercent)
        if case .showing(var show) = state.phase {
            if let trigger, trigger != show.trigger {
                let effect = present(&state, trigger, percent: percent, sample: sample, at: at)
                return (state, [effect])
            }
            show.percent = percent
            show.charging = sample.charging
            show.accessibilityLabel = label(show.trigger, percent)
            state.phase = .showing(show)
            return (state, [])
        }
        guard let trigger else { return (state, []) }
        let effect = present(&state, trigger, percent: percent, sample: sample, at: at)
        return (state, [effect])
    }

    private static func trigger(previous: BatteryPowerSample?, sample: BatteryPowerSample, percent: Int, lastLow: Int?) -> BatteryOverlayTrigger? {
        if let previous, previous.onAC != sample.onAC {
            return sample.onAC ? .chargerConnected : .chargerDisconnected
        }
        if !sample.onAC, percent <= lowBatteryAt, lastLow != percent { return .lowBattery }
        return nil
    }

    private static func present(_ state: inout BatteryOverlayMachine, _ trigger: BatteryOverlayTrigger, percent: Int, sample: BatteryPowerSample, at: TimeInterval) -> Effect {
        if trigger == .lowBattery { state.lastLowPercent = percent }
        let show = BatteryOverlayShow(
            trigger: trigger,
            style: state.style,
            percent: percent,
            charging: sample.charging,
            until: at + showDuration,
            animationDuration: BatteryMotion.duration(reduceMotion: state.reduceMotion, style: state.style),
            accessibilityLabel: label(trigger, percent)
        )
        state.phase = .showing(show)
        return .present(show)
    }

    private static func label(_ trigger: BatteryOverlayTrigger, _ percent: Int) -> String {
        switch trigger {
        case .chargerConnected: "Charging, \(percent) percent"
        case .chargerDisconnected: "On battery, \(percent) percent"
        case .lowBattery: "Battery low, \(percent) percent"
        }
    }
}

public enum BatteryOverlayAction: Equatable, Sendable {
    case showCharging(percent: Int, style: BatteryOverlayStyle)
    case showLowBattery(percent: Int, style: BatteryOverlayStyle)
    case flashGauge(level: Double, charging: Bool)
    case dismiss
}

/// Maps a show onto the cue and the outline Zeus already has. Ring and readout skip the outline.
public enum BatteryOverlayHostPlan {
    public static func actions(for effects: [BatteryOverlayMachine.Effect]) -> [BatteryOverlayAction] {
        effects.flatMap { effect -> [BatteryOverlayAction] in
            switch effect {
            case .dismiss:
                return [.dismiss]
            case .present(let show):
                switch show.trigger {
                case .chargerConnected:
                    var actions: [BatteryOverlayAction] = [.showCharging(percent: show.percent, style: show.style)]
                    if show.style == .gauge {
                        actions.append(.flashGauge(level: Double(show.percent) / 100, charging: true))
                    }
                    return actions
                case .chargerDisconnected:
                    guard show.style == .gauge else { return [] }
                    return [.flashGauge(level: Double(show.percent) / 100, charging: false)]
                case .lowBattery:
                    return [.showLowBattery(percent: show.percent, style: show.style)]
                }
            }
        }
    }
}
