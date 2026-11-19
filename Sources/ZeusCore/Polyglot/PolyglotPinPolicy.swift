import Foundation

/// The notch events that consult the pin. Each one is routed through `PolyglotPinPolicy` by the app.
public enum PolyglotPinTrigger: Sendable, Equatable {
    /// The pointer is outside the open panel (the mouse-move monitor).
    case pointerExited
    /// Automatic dismissal, including a click elsewhere with auto-hide off.
    case clickedOutside
    /// The Dismiss button on the Polyglot bar.
    case explicitDismiss
}

/// The facts the pin decision needs. Pure data: no UI, no capture.
public struct PolyglotPinContext: Sendable, Equatable {
    public var isPolyglotTabSelected: Bool
    public var isPinned: Bool
    public var autoHideEnabled: Bool

    public init(isPolyglotTabSelected: Bool, isPinned: Bool, autoHideEnabled: Bool) {
        self.isPolyglotTabSelected = isPolyglotTabSelected
        self.isPinned = isPinned
        self.autoHideEnabled = autoHideEnabled
    }
}

public enum PolyglotPinDecision: Sendable, Equatable {
    /// Hide the bar now.
    case close
    /// Start (or keep) the automatic-hide countdown.
    case scheduleClose
    /// Leave the bar as it is and drop any pending automatic close.
    case keepOpen
}

/// Pin and automatic-hide rules for the Polyglot bar. A pin only holds on the Polyglot page;
/// only an explicit dismiss closes a pinned bar.
public enum PolyglotPinPolicy {
    public static func keepsOpen(_ context: PolyglotPinContext) -> Bool {
        context.isPolyglotTabSelected && context.isPinned
    }

    public static func decide(_ trigger: PolyglotPinTrigger, _ context: PolyglotPinContext) -> PolyglotPinDecision {
        switch trigger {
        case .explicitDismiss:
            return .close
        case .clickedOutside:
            return keepsOpen(context) ? .keepOpen : .close
        case .pointerExited:
            if keepsOpen(context) { return .keepOpen }
            return context.autoHideEnabled ? .scheduleClose : .keepOpen
        }
    }
}
