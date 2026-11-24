import Foundation

/// What one Command or talk press should do with the voice permission it sees.
///
/// A press that already arrived can start, ask, or degrade. Asking is not a finished
/// turn: `recover` starts it only when the answer is ready and the key is still down.
/// A denial does not start a turn and does not ask again.
public enum CommandHotkeyAccess {
    public enum Voice: Equatable, Sendable {
        case ready
        case needsPrompt
        case denied
    }

    public enum Step: Equatable, Sendable {
        case start
        case ask
        case degradeVoice
        case wait
    }

    public static func press(voice: Voice) -> Step {
        switch voice {
        case .ready: .start
        case .needsPrompt: .ask
        case .denied: .degradeVoice
        }
    }

    /// After the prompt. A ready answer starts the turn only while the key is still held.
    /// Denied stays denied. A key that came up waits for the next press.
    public static func recover(voice: Voice, keyStillDown: Bool) -> Step {
        switch voice {
        case .ready: keyStillDown ? .start : .wait
        case .needsPrompt: .wait
        case .denied: .degradeVoice
        }
    }
}

/// Arms global key monitors once Accessibility or Input Monitoring is on.
///
/// Missing access announces once and does not arm. A later grant arms the monitors and
/// clears a press that got stuck while no events could arrive. A second grant does not
/// arm again.
public struct KeyListenRecovery: Equatable, Sendable {
    public private(set) var armed = false
    public private(set) var announcedMissing = false

    public init() {}

    public enum Event: Equatable, Sendable {
        case start(granted: Bool)
        case granted
    }

    public enum Effect: Equatable, Sendable {
        case armMonitors
        case announceMissing
        case clearStuckPress
    }

    public mutating func send(_ event: Event) -> [Effect] {
        switch event {
        case .start(let granted):
            if granted { return arm() }
            guard !announcedMissing else { return [] }
            announcedMissing = true
            return [.announceMissing]
        case .granted:
            return arm(clearingStuckPress: true)
        }
    }

    private mutating func arm(clearingStuckPress: Bool = false) -> [Effect] {
        guard !armed else { return [] }
        armed = true
        var effects: [Effect] = [.armMonitors]
        if clearingStuckPress { effects.append(.clearStuckPress) }
        return effects
    }
}

/// The generation `injectDictationFile` must keep so the latency lines can flush.
/// Zero is unset. `noteDelivered` refuses it, so the lines never appear.
public enum DictateFileTrace {
    public static func keep(_ noted: Int) -> Int { noted > 0 ? noted : 0 }
}
