import Foundation

/// Play Demo moments that are drawn on screen and spoken.
/// The bolt gets the short line. The voice gets the sentence.
public enum PlayDemoScript {
    public struct Step: Equatable, Sendable {
        public var spoken: String
        public var bolt: String
        /// Drawn on screen. A step that is only spoken is not this demo.
        public var showsOnScreen: Bool

        public init(spoken: String, bolt: String, showsOnScreen: Bool) {
            self.spoken = spoken
            self.bolt = bolt
            self.showsOnScreen = showsOnScreen
        }
    }

    public static let listening = Step(
        spoken: "Hold the talk key, then speak. I'll listen.",
        bolt: "Listening",
        showsOnScreen: true
    )

    public static let thinking = Step(
        spoken: "One moment. I'm working out what to show you.",
        bolt: "Thinking",
        showsOnScreen: true
    )

    public static let menuBar = Step(
        spoken: "That's me up here. Click the bolt anytime.",
        bolt: "Click the bolt anytime",
        showsOnScreen: true
    )

    public static let allowed = Step(
        spoken: "Allowed. The build is running, and I'll show you when it finishes.",
        bolt: "Allowed",
        showsOnScreen: true
    )

    public static let denied = Step(
        spoken: "Denied. I left that command alone, so nothing was removed.",
        bolt: "Denied",
        showsOnScreen: true
    )

    public static let building = Step(
        spoken: "Claude Code started the build. I'll point at Approve when it asks.",
        bolt: "Building",
        showsOnScreen: true
    )

    public static let approvalMissing = Step(
        spoken: "I couldn't find Approve on screen, so I'll keep going.",
        bolt: "Not found",
        showsOnScreen: true
    )

    public static let approval = Step(
        spoken: "This needs you. Approve or deny, or just say ok.",
        bolt: "Approve or deny, or say ok",
        showsOnScreen: true
    )

    public static let panel = Step(
        spoken: "Codex and Cursor are working too. I'll open the panel.",
        bolt: "More agents",
        showsOnScreen: true
    )

    public static let peek = Step(
        spoken: "Here's Codex. It's writing tests for checkout.",
        bolt: "Codex",
        showsOnScreen: true
    )

    public static let closed = Step(
        spoken: "That's the tour. I'll put the notch away.",
        bolt: "Closed",
        showsOnScreen: true
    )

    /// Ready when the step is drawn and the bolt line is a caption the overlay can show.
    public static func ready(_ step: Step) -> Bool {
        guard step.showsOnScreen, !step.spoken.isEmpty else { return false }
        return PointerGuideCaptionSplit.boltText(step.bolt) == step.bolt
    }
}
