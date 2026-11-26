import Foundation

/// The words and symbols the notch and the settings row draw. Width stays with the view.
/// A missing name becomes "Focus on". A missing symbol becomes the moon. Nothing here is cut.
public enum SystemFocusDisplay {
    public enum Shown: Equatable, Sendable {
        case none
        case on(label: String, symbol: String)
    }

    public enum Row: Equatable, Sendable {
        case off
        case checking
        case allowed
        case needsAccess
        case unavailable
    }

    public struct Surface: Equatable, Sendable {
        public var shown: Shown
        public var row: Row

        public init(shown: Shown, row: Row) {
            self.shown = shown
            self.row = row
        }
    }

    public static let plainSymbol = "moon.fill"
    public static let offSymbol = "moon"
    public static let onLabel = "Focus on"
    public static let offLabel = "Focus off"

    /// Shown only while the route is named and the reading is on. Unknown draws nothing.
    public static func surface(for state: SystemFocusMachine.State) -> Surface {
        Surface(shown: shown(for: state), row: row(for: state.route))
    }

    public static func cue(
        for edge: SystemFocusEdge,
        reading: SystemFocusMachine.Reading,
        hidden: Bool
    ) -> SystemFocusMachine.Cue {
        switch edge {
        case .turnedOn, .replaced:
            let presented = presentation(reading: reading, hidden: hidden)
            return SystemFocusMachine.Cue(label: presented.label, symbol: presented.symbol, on: true)
        case .turnedOff:
            return SystemFocusMachine.Cue(label: offLabel, symbol: offSymbol, on: false)
        }
    }

    public static func rowWord(_ state: SystemFocusMachine.State) -> String? {
        switch row(for: state.route) {
        case .allowed: return "Allowed"
        case .needsAccess: return "Not allowed"
        case .unavailable: return "Not available on this macOS"
        case .off, .checking: return nil
        }
    }

    public static func rowSymbol(_ state: SystemFocusMachine.State) -> String? {
        switch row(for: state.route) {
        case .allowed: return "checkmark.circle.fill"
        case .needsAccess, .unavailable: return "exclamationmark.circle"
        case .off, .checking: return nil
        }
    }

    /// "Focus on, Work", "Focus on", or "Focus off". The view keeps the full string.
    public static func accessibilityLabel(_ state: SystemFocusMachine.State) -> String {
        guard case .named = state.route, case .on(let focus) = state.reading else { return offLabel }
        if state.detailsHidden { return onLabel }
        guard let name = focus.name, !name.isEmpty else { return onLabel }
        return "\(onLabel), \(name)"
    }

    // MARK: Pieces

    private static func row(for route: SystemFocusMachine.Route) -> Row {
        switch route {
        case .off: return .off
        case .checking: return .checking
        case .named: return .allowed
        case .needsAccess: return .needsAccess
        case .unavailable: return .unavailable
        }
    }

    private static func shown(for state: SystemFocusMachine.State) -> Shown {
        guard case .named = state.route, case .on(let focus) = state.reading else { return .none }
        let presented = presentation(focus: focus, hidden: state.detailsHidden)
        return .on(label: presented.label, symbol: presented.symbol)
    }

    private static func presentation(
        reading: SystemFocusMachine.Reading,
        hidden: Bool
    ) -> (label: String, symbol: String) {
        guard case .on(let focus) = reading else { return (onLabel, plainSymbol) }
        return presentation(focus: focus, hidden: hidden)
    }

    private static func presentation(
        focus: SystemFocusMachine.Focus,
        hidden: Bool
    ) -> (label: String, symbol: String) {
        if hidden { return (onLabel, plainSymbol) }
        let label = focus.name.flatMap { $0.isEmpty ? nil : $0 } ?? onLabel
        let symbol = focus.symbol.flatMap { $0.isEmpty ? nil : $0 } ?? plainSymbol
        return (label, symbol)
    }
}
