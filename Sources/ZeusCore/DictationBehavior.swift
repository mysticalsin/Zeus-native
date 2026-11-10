/// How the dedicated dictation shortcut controls a recording.
public enum DictationBehavior: String, CaseIterable, Equatable, Identifiable, Sendable {
    case holdToSpeak
    case pressToToggle

    public enum PressAction: Equatable, Sendable { case begin, finish }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .holdToSpeak: "Hold to speak"
        case .pressToToggle: "Press to start and stop"
        }
    }

    public var detail: String {
        switch self {
        case .holdToSpeak: "Hold the key while speaking; release to transcribe."
        case .pressToToggle: "Press once to start recording and again to finish."
        }
    }

    public func actionOnPress(isDictating: Bool) -> PressAction {
        switch self {
        case .holdToSpeak: .begin
        case .pressToToggle: isDictating ? .finish : .begin
        }
    }

    public var finishesOnRelease: Bool { self == .holdToSpeak }

    /// A key shared with the talk shortcut keeps its hold/double-tap contract.
    public static func choices(sharedWithTalkKey: Bool) -> [DictationBehavior] {
        sharedWithTalkKey ? [.holdToSpeak] : allCases
    }
}
