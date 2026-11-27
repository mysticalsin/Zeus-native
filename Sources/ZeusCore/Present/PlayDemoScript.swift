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

    public static let approval = Step(
        spoken: "This needs you. Approve or deny, or just say ok.",
        bolt: "Approve or deny, or say ok",
        showsOnScreen: true
    )

    /// Ready when the step is drawn and the bolt line is a caption the overlay can show.
    public static func ready(_ step: Step) -> Bool {
        guard step.showsOnScreen, !step.spoken.isEmpty else { return false }
        return PointerGuideCaptionSplit.boltText(step.bolt) == step.bolt
    }
}
