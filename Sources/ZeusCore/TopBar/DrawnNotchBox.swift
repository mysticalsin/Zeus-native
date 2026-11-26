import Foundation

/// Ranges, snap, fit, position words, calibration, and whether a drawn notch can be shown.
/// The drawn label is the five scalars of "Notch". A blank scalar is not removed first:
/// space (U+0020), tab (U+0009), line feed (U+000A), carriage return (U+000D), and the
/// zero-width space (U+200B). Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so this box names the scalars instead.
/// The box takes the shape, the display width, and the open panel width. It does not read a screen, a pointer, a clock, or a stored setting.
public enum DrawnNotchBox {
    public static let widthRange: ClosedRange<Double> = 140...280
    public static let widthStep = 5.0
    /// Never under 30: every closed wing is laid out for a 30 pt bar.
    public static let heightRange: ClosedRange<Double> = 30...44
    public static let heightStep = 1.0
    public static let offsetRange: ClosedRange<Double> = -400...400
    public static let offsetStep = 5.0

    /// The closed notch size, centred.
    public static let defaultShape = DrawnNotchShape(width: 185, height: 32, offset: 0)

    /// Room kept between the shifted notch and the display's edge.
    private static let edgeMargin = 8.0

    public static let savedAnnouncement = "Notch shape saved"
    public static let unchangedAnnouncement = "Notch shape unchanged"

    /// Exact label. "Notch" is drawn. Anything else, including a trailing blank scalar, is the pill.
    public static func style(label: String) -> NotchlessStyle {
        label == "Notch" ? .drawn : .pill
    }

    /// Finite, on the step and inside the range. A field that is not finite takes its default.
    public static func sanitized(_ shape: DrawnNotchShape) -> DrawnNotchShape {
        DrawnNotchShape(width: width(shape.width), height: height(shape.height), offset: offset(shape.offset))
    }

    /// "Centre", or a distance and a side. `unit` is kept as given, including a zero-width space.
    public static func positionText(_ value: Double, unit: String = "pt") -> String {
        let snapped = offset(value)
        guard snapped != 0 else { return "Centre" }
        return "\(Int(abs(snapped))) \(unit) \(snapped < 0 ? "left" : "right")"
    }

    /// Never wider than a quarter of the display (snapped down), and shifted no further than `panelWidth`
    /// leaves room for (snapped toward zero). Nil when the display is not finite or cannot hold the narrowest shape.
    public static func fitted(_ shape: DrawnNotchShape, screenWidth: Double, panelWidth: Double) -> DrawnNotchShape? {
        guard screenWidth.isFinite else { return nil }
        let widest = (screenWidth / 4 / widthStep).rounded(.down) * widthStep
        guard widest >= widthRange.lowerBound else { return nil }
        let clean = sanitized(shape)
        let room = max(0, (screenWidth - panelWidth) / 2 - edgeMargin)
        let reach = (room / offsetStep).rounded(.towardZero) * offsetStep
        return DrawnNotchShape(width: min(clean.width, widest), height: clean.height,
                               offset: min(max(clean.offset, -reach), reach))
    }

    public static func reduce(
        _ state: DrawnNotchCalibration.State, _ event: DrawnNotchCalibration.Event
    ) -> (DrawnNotchCalibration.State, [DrawnNotchCalibration.Effect]) {
        switch (state, event) {
        case (.idle, .begin(let saved)):
            let clean = sanitized(saved)
            return (.adjusting(draft: clean, saved: clean), [])
        case (.idle, _):
            return (.idle, [])
        case (.adjusting, .begin):
            return (state, [])
        case (.adjusting(var draft, let saved), .setWidth(let value)):
            draft.width = width(value)
            return (.adjusting(draft: draft, saved: saved), [])
        case (.adjusting(var draft, let saved), .setHeight(let value)):
            draft.height = height(value)
            return (.adjusting(draft: draft, saved: saved), [])
        case (.adjusting(var draft, let saved), .setOffset(let value)):
            draft.offset = offset(value)
            return (.adjusting(draft: draft, saved: saved), [])
        case (.adjusting(var draft, let saved), .step(let field, let direction)):
            let sign: Double = direction == .up ? 1 : -1
            switch field {
            case .width: draft.width = width(draft.width + sign * widthStep)
            case .height: draft.height = height(draft.height + sign * heightStep)
            case .offset: draft.offset = offset(draft.offset + sign * offsetStep)
            }
            return (.adjusting(draft: draft, saved: saved), [])
        case (.adjusting(_, let saved), .reset):
            return (.adjusting(draft: defaultShape, saved: saved), [])
        case (.adjusting(let draft, let saved), .done):
            guard draft != saved else { return (.idle, [.announce(unchangedAnnouncement)]) }
            return (.idle, [.persist(draft), .announce(savedAnnouncement)])
        case (.adjusting, .cancel), (.adjusting, .surfaceGone):
            return (.idle, [])
        }
    }

    /// The draft while adjusting, else the saved shape.
    public static func shown(_ state: DrawnNotchCalibration.State, saved: DrawnNotchShape) -> DrawnNotchShape {
        if case .adjusting(let draft, _) = state { return draft }
        return saved
    }

    /// The guide outline shows that calibration is running.
    public static func showsGuide(_ state: DrawnNotchCalibration.State) -> Bool {
        if case .adjusting = state { return true }
        return false
    }

    /// The pointer opens the notch only when it is not being calibrated.
    public static func allowsOpen(_ state: DrawnNotchCalibration.State) -> Bool {
        !showsGuide(state)
    }

    public static func availability(targetsWithoutNotch: Int, connectedWithoutNotch: Int) -> DrawnNotchAvailability {
        if connectedWithoutNotch <= 0 { return .noDisplay }
        if targetsWithoutNotch <= 0 { return .notShown }
        return .ready
    }

    private static func snapped(_ value: Double, step: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        let onStep = (value / step).rounded() * step
        return min(max(onStep, range.lowerBound), range.upperBound)
    }

    private static func width(_ value: Double) -> Double {
        snapped(value, step: widthStep, range: widthRange, fallback: defaultShape.width)
    }

    private static func height(_ value: Double) -> Double {
        snapped(value, step: heightStep, range: heightRange, fallback: defaultShape.height)
    }

    private static func offset(_ value: Double) -> Double {
        snapped(value, step: offsetStep, range: offsetRange, fallback: defaultShape.offset)
    }
}
