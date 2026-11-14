import Foundation

/// What a display without a notch shows at the top centre: the slim pill, or a notch silhouette the owner drew.
public enum NotchlessStyle: Sendable, Equatable {
    case pill
    case drawn

    /// The stored display string. Anything unknown is the pill, today's behaviour.
    public init(label: String) {
        self = label == "Notch" ? .drawn : .pill
    }
}

/// The drawn notch's size and sideways position, in points. One global value, not one per display.
public struct DrawnNotchShape: Sendable, Equatable {
    public var width: Double
    public var height: Double
    public var offset: Double

    public init(width: Double, height: Double, offset: Double) {
        self.width = width
        self.height = height
        self.offset = offset
    }
}

/// The ranges, steps and defaults of the drawn notch, and how a shape is made to fit them and a display.
public enum DrawnNotchLimits {
    public static let widthRange: ClosedRange<Double> = 140...280
    public static let widthStep = 5.0
    /// Never under 30: every closed wing is laid out for a 30 pt bar.
    public static let heightRange: ClosedRange<Double> = 30...44
    public static let heightStep = 1.0
    public static let offsetRange: ClosedRange<Double> = -400...400
    public static let offsetStep = 5.0

    /// The closed notch size of `GlanceTopBar.closedSize`, centred.
    public static let defaultShape = DrawnNotchShape(width: 185, height: 32, offset: 0)

    /// The open panel with its ears: the widest the top bar gets.
    private static let panelWidth = Double(GlanceTopBar.bodyWidth + 2 * GlanceTopBar.ear)
    /// Room kept between the shifted notch and the display's edge.
    private static let edgeMargin = 8.0

    private static func snapped(_ value: Double, step: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        let onStep = (value / step).rounded() * step
        return min(max(onStep, range.lowerBound), range.upperBound)
    }

    static func width(_ value: Double) -> Double {
        snapped(value, step: widthStep, range: widthRange, fallback: defaultShape.width)
    }

    static func height(_ value: Double) -> Double {
        snapped(value, step: heightStep, range: heightRange, fallback: defaultShape.height)
    }

    static func offset(_ value: Double) -> Double {
        snapped(value, step: offsetStep, range: offsetRange, fallback: defaultShape.offset)
    }

    /// Finite, on the step and inside the range. A field that is not finite takes its default.
    public static func sanitized(_ shape: DrawnNotchShape) -> DrawnNotchShape {
        DrawnNotchShape(width: width(shape.width), height: height(shape.height), offset: offset(shape.offset))
    }

    /// The shape on one display: never wider than a quarter of it (snapped down), and shifted no further than
    /// the open panel with its ears leaves room for (snapped toward zero). Nil when the display is not finite
    /// or cannot hold the narrowest shape: that display keeps the pill.
    public static func fitted(_ shape: DrawnNotchShape, screenWidth: Double) -> DrawnNotchShape? {
        guard screenWidth.isFinite else { return nil }
        let widest = (screenWidth / 4 / widthStep).rounded(.down) * widthStep
        guard widest >= widthRange.lowerBound else { return nil }
        let clean = sanitized(shape)
        let room = max(0, (screenWidth - panelWidth) / 2 - edgeMargin)
        let reach = (room / offsetStep).rounded(.towardZero) * offsetStep
        return DrawnNotchShape(width: min(clean.width, widest), height: clean.height,
                               offset: min(max(clean.offset, -reach), reach))
    }
}

/// Calibration: the owner starts it, adjusts a draft and ends it with Done or Cancel. Anything that takes away the
/// card or the shape ends it without saving. Pure: a controller performs the effects.
public enum DrawnNotchCalibration {
    public enum State: Sendable, Equatable {
        case idle
        case adjusting(draft: DrawnNotchShape, saved: DrawnNotchShape)
    }

    /// Why the card or the shape went away. Logged by name; every case has the same result.
    public enum SurfaceLoss: String, Sendable, CaseIterable {
        case pageLeft, settingsClosed, settingsMinimised, appHidden, pillChosen, noDisplay, locked, sleeping, sessionResigned
    }

    public enum Field: Sendable, Equatable, CaseIterable {
        case width, height, offset
    }

    public enum Direction: Sendable, Equatable {
        case up, down
    }

    public enum Event: Sendable, Equatable {
        case begin(saved: DrawnNotchShape)
        case setWidth(Double)
        case setHeight(Double)
        case setOffset(Double)
        case step(Field, Direction)
        case reset
        case done
        case cancel
        case surfaceGone(SurfaceLoss)
    }

    public enum Effect: Sendable, Equatable {
        case persist(DrawnNotchShape)
        case announce(String)
    }

    public static let savedAnnouncement = "Notch shape saved"
    public static let unchangedAnnouncement = "Notch shape unchanged"

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch (state, event) {
        case (.idle, .begin(let saved)):
            let clean = DrawnNotchLimits.sanitized(saved)
            return (.adjusting(draft: clean, saved: clean), [])
        case (.idle, _):
            return (.idle, [])
        case (.adjusting, .begin):
            return (state, [])
        case (.adjusting(var draft, let saved), .setWidth(let value)):
            draft.width = DrawnNotchLimits.width(value)
            return (.adjusting(draft: draft, saved: saved), [])
        case (.adjusting(var draft, let saved), .setHeight(let value)):
            draft.height = DrawnNotchLimits.height(value)
            return (.adjusting(draft: draft, saved: saved), [])
        case (.adjusting(var draft, let saved), .setOffset(let value)):
            draft.offset = DrawnNotchLimits.offset(value)
            return (.adjusting(draft: draft, saved: saved), [])
        case (.adjusting(var draft, let saved), .step(let field, let direction)):
            let sign: Double = direction == .up ? 1 : -1
            switch field {
            case .width: draft.width = DrawnNotchLimits.width(draft.width + sign * DrawnNotchLimits.widthStep)
            case .height: draft.height = DrawnNotchLimits.height(draft.height + sign * DrawnNotchLimits.heightStep)
            case .offset: draft.offset = DrawnNotchLimits.offset(draft.offset + sign * DrawnNotchLimits.offsetStep)
            }
            return (.adjusting(draft: draft, saved: saved), [])
        case (.adjusting(_, let saved), .reset):
            return (.adjusting(draft: DrawnNotchLimits.defaultShape, saved: saved), [])
        case (.adjusting(let draft, let saved), .done):
            guard draft != saved else { return (.idle, [.announce(unchangedAnnouncement)]) }
            return (.idle, [.persist(draft), .announce(savedAnnouncement)])
        case (.adjusting, .cancel), (.adjusting, .surfaceGone):
            return (.idle, [])
        }
    }

    /// The draft while adjusting, else the saved shape.
    public static func shown(_ state: State, saved: DrawnNotchShape) -> DrawnNotchShape {
        if case .adjusting(let draft, _) = state { return draft }
        return saved
    }

    /// The guide outline shows that calibration is running.
    public static func showsGuide(_ state: State) -> Bool {
        if case .adjusting = state { return true }
        return false
    }

    /// The pointer opens the notch only when it is not being calibrated.
    public static func allowsOpen(_ state: State) -> Bool {
        !showsGuide(state)
    }
}

/// Whether a drawn notch can be seen right now, and if not, why.
public enum DrawnNotchAvailability: Sendable, Equatable {
    /// The notch is shown on a display without a notch.
    case ready
    /// Such a display is connected but is not a target of "Show the notch on".
    case notShown
    /// No display without a notch is connected.
    case noDisplay

    public static func resolve(targetsWithoutNotch: Int, connectedWithoutNotch: Int) -> DrawnNotchAvailability {
        if connectedWithoutNotch <= 0 { return .noDisplay }
        if targetsWithoutNotch <= 0 { return .notShown }
        return .ready
    }
}

/// The seam between the notch model and the Settings card, so the two compile apart.
@MainActor
public protocol DrawnNotchControlling: AnyObject {
    var style: NotchlessStyle { get }
    var saved: DrawnNotchShape { get }
    var state: DrawnNotchCalibration.State { get }
    var availability: DrawnNotchAvailability { get }
    func setStyle(_ style: NotchlessStyle)
    func send(_ event: DrawnNotchCalibration.Event)
}
