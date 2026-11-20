import Foundation

/// What a key does in the preview card.
public enum DictationPreviewKey: Equatable, Sendable {
    case insert
    case cancel
    /// Let the text field handle it (typing, Shift+Return for a new line).
    case edit

    public static func action(keyCode: UInt16, shift: Bool, command: Bool) -> DictationPreviewKey {
        switch keyCode {
        case 36, 76: return shift && !command ? .edit : .insert  // Return, Enter
        case 53: return .cancel                                   // Escape
        default: return .edit
        }
    }
}

/// Hands focus back to the app you dictated into before the text goes in. The preview card
/// briefly takes focus, so ZEUS reactivates the target and waits until it is really in front;
/// if it never comes back, the text is only copied, never typed into the wrong app.
public enum FrontmostHandoff {
    public enum State: Equatable, Sendable {
        case checking(remaining: Int)
        case finalLook
        case matched
        case unmatched
    }

    public enum Event: Equatable, Sendable {
        case hit
        case miss
    }

    public enum Effect: Equatable, Sendable {
        case sleep
    }

    /// No target is already unmatched. A non-positive attempt count still checks once.
    public static func start(target: String?, attempts: Int) -> State {
        guard target != nil else { return .unmatched }
        return .checking(remaining: max(attempts, 1))
    }

    /// Matched and unmatched ignore later observations. A miss on the last loop check sleeps, then looks once more.
    public static func reduce(_ state: State, _ event: Event) -> (State, Effect?) {
        switch (state, event) {
        case (.checking, .hit), (.finalLook, .hit):
            return (.matched, nil)
        case (.checking(let remaining), .miss) where remaining > 1:
            return (.checking(remaining: remaining - 1), .sleep)
        case (.checking, .miss):
            return (.finalLook, .sleep)
        case (.finalLook, .miss):
            return (.unmatched, nil)
        case (.matched, _), (.unmatched, _):
            return (state, nil)
        }
    }

    @MainActor
    public static func waitUntilFrontmost(target: String?, current: () -> String?, attempts: Int = 12,
                                          sleep: () async -> Void) async -> Bool {
        var state = start(target: target, attempts: attempts)
        while true {
            switch state {
            case .matched:
                return true
            case .unmatched:
                return false
            case .checking, .finalLook:
                let (next, effect) = reduce(state, current() == target ? .hit : .miss)
                state = next
                if effect == .sleep { await sleep() }
            }
        }
    }
}

/// The text that goes in after review: trimmed; nothing when it was emptied.
public enum DictationPreviewResult {
    public static func finalText(_ edited: String) -> String? {
        let trimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
