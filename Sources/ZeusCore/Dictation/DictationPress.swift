import Foundation

/// What the top-bar Dictate control does, and the words it shows, for one phase.
///
/// A press used to finish only while listening and begin only while idle. Transcribing and
/// rewriting count as dictating, so the control did nothing and VoiceOver still said "Start dictation"
/// while the button read "Typing". The action and the label both come from the phase.
public enum DictationPress {
    public enum Action: Equatable, Sendable {
        case begin
        case finish
        case cancel
    }

    public struct Copy: Equatable, Sendable {
        public var title: String
        public var accessibilityLabel: String
        public var help: String
    }

    public static func action(for phase: DictationPhase) -> Action {
        switch phase {
        case .listening: .finish
        case .transcribing, .rewriting: .cancel
        case .idle, .done, .failed: .begin
        }
    }

    /// The title is the word the button already draws. The accessibility label names that same phase.
    public static func label(for phase: DictationPhase, holding: Bool) -> Copy {
        switch phase {
        case .listening:
            return Copy(title: holding ? "Release" : "Stop",
                        accessibilityLabel: "Stop dictation",
                        help: "Stop and type it")
        case .transcribing, .rewriting:
            return Copy(title: "Typing",
                        accessibilityLabel: "Typing",
                        help: "Cancel typing")
        case .idle, .done, .failed:
            return Copy(title: "Dictate",
                        accessibilityLabel: "Start dictation",
                        help: "Dictate into the app you're in")
        }
    }
}
