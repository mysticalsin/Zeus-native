import Foundation

/// What VoiceOver reads for one Integrations control, and the Reduce Motion rule for its toggle.
/// Pure text: the settings page speaks these words, and a Mac still has to show the focus ring.
public struct ConnectionControlSpeech: Equatable, Sendable {
    public var label: String
    public var value: String
    public var hint: String

    public init(label: String, value: String, hint: String) {
        self.label = label
        self.value = value
        self.hint = hint
    }

    /// Offer toggles change position immediately when Reduce Motion is on.
    public static let reducedMotionToggleSeconds = 0.0

    public static func primary(provider: String, action: String, detail: String, busy: Bool) -> ConnectionControlSpeech {
        if busy {
            return ConnectionControlSpeech(
                label: "Checking \(provider)",
                value: "Busy",
                hint: "Wait for the check of \(provider) to finish.")
        }
        return ConnectionControlSpeech(
            label: "\(action) \(provider)",
            value: detail,
            hint: "\(action) \(provider).")
    }

    public static func status(provider: String, text: String) -> String {
        "\(provider), \(text)"
    }

    public static func field(provider: String, field: String) -> String {
        "\(provider) \(field)"
    }
}
