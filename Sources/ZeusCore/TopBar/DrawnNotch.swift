import Foundation

/// What a display without a notch shows at the top centre: the slim pill, or a notch silhouette the owner drew.
/// The label is read from `DrawnNotchBox`.
public enum NotchlessStyle: Sendable, Equatable {
    case pill
    case drawn

    /// The stored display string. Anything unknown is the pill, today's behaviour.
    public init(label: String) {
        self = DrawnNotchBox.style(label: label)
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
/// Each answer is read from `DrawnNotchBox`. The open panel width still comes from `GlanceTopBar`.
public enum DrawnNotchLimits {
    public static let widthRange: ClosedRange<Double> = DrawnNotchBox.widthRange
    public static let widthStep = DrawnNotchBox.widthStep
    /// Never under 30: every closed wing is laid out for a 30 pt bar.
    public static let heightRange: ClosedRange<Double> = DrawnNotchBox.heightRange
    public static let heightStep = DrawnNotchBox.heightStep
    public static let offsetRange: ClosedRange<Double> = DrawnNotchBox.offsetRange
    public static let offsetStep = DrawnNotchBox.offsetStep

    /// The closed notch size of `GlanceTopBar.closedSize`, centred.
    public static let defaultShape = DrawnNotchBox.defaultShape

    /// The open panel with its ears: the widest the top bar gets.
    private static let panelWidth = Double(GlanceTopBar.bodyWidth + 2 * GlanceTopBar.ear)

    /// Finite, on the step and inside the range. A field that is not finite takes its default.
    public static func sanitized(_ shape: DrawnNotchShape) -> DrawnNotchShape {
        DrawnNotchBox.sanitized(shape)
    }

    /// The position as the owner reads it: "Centre", or a distance and a side. `unit` is "pt" on screen and
    /// "points" for VoiceOver. A value off the step or the range reads as the one it snaps to.
    public static func positionText(_ value: Double, unit: String = "pt") -> String {
        DrawnNotchBox.positionText(value, unit: unit)
    }

    /// The shape on one display: never wider than a quarter of it (snapped down), and shifted no further than
    /// the open panel with its ears leaves room for (snapped toward zero). Nil when the display is not finite
    /// or cannot hold the narrowest shape: that display keeps the pill.
    public static func fitted(_ shape: DrawnNotchShape, screenWidth: Double) -> DrawnNotchShape? {
        DrawnNotchBox.fitted(shape, screenWidth: screenWidth, panelWidth: panelWidth)
    }
}

/// Calibration: the owner starts it, adjusts a draft and ends it with Done or Cancel. Anything that takes away the
/// card or the shape ends it without saving. Pure: a controller performs the effects.
/// Each step is read from `DrawnNotchBox`.
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

    public static let savedAnnouncement = DrawnNotchBox.savedAnnouncement
    public static let unchangedAnnouncement = DrawnNotchBox.unchangedAnnouncement

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        DrawnNotchBox.reduce(state, event)
    }

    /// The draft while adjusting, else the saved shape.
    public static func shown(_ state: State, saved: DrawnNotchShape) -> DrawnNotchShape {
        DrawnNotchBox.shown(state, saved: saved)
    }

    /// The guide outline shows that calibration is running.
    public static func showsGuide(_ state: State) -> Bool {
        DrawnNotchBox.showsGuide(state)
    }

    /// The pointer opens the notch only when it is not being calibrated.
    public static func allowsOpen(_ state: State) -> Bool {
        DrawnNotchBox.allowsOpen(state)
    }
}

/// Whether a drawn notch can be seen right now, and if not, why.
/// The answer is read from `DrawnNotchBox`.
public enum DrawnNotchAvailability: Sendable, Equatable {
    /// The notch is shown on a display without a notch.
    case ready
    /// Such a display is connected but is not a target of "Show the notch on".
    case notShown
    /// No display without a notch is connected.
    case noDisplay

    public static func resolve(targetsWithoutNotch: Int, connectedWithoutNotch: Int) -> DrawnNotchAvailability {
        DrawnNotchBox.availability(targetsWithoutNotch: targetsWithoutNotch, connectedWithoutNotch: connectedWithoutNotch)
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
