import Foundation

/// Who is using the microphone input while Zeus records, as a pure state machine.
///
/// Rules:
/// - Zeus holds the input only between `.zeusStarted` and `.zeusStopped`; `.zeusStopped` always releases it.
/// - Another app using the microphone never takes it away from Zeus: macOS shares the input between apps.
/// - Nothing latches. `.otherApp(active: false)` clears the shared state at once, and a new recording starts
///   from what the latest reading says, never from what an earlier recording saw.
/// - A default input device change rebuilds Zeus's input only while Zeus holds it.
public struct MicInputOwnership: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case released
        case listening
    }

    public enum Event: Equatable, Sendable {
        case zeusStarted
        case zeusStopped
        /// The latest reading of whether any other app is capturing the microphone.
        case otherApp(active: Bool)
        /// The default input device (or its format) changed.
        case defaultInputChanged
    }

    public enum Effect: Equatable, Sendable {
        case openInput
        case closeInput
        case reopenInput
        /// Whether the microphone is now shared with another app (reported on change only).
        case sharedChanged(Bool)
    }

    public private(set) var phase: Phase = .released
    public private(set) var otherAppActive = false

    public init() {}

    /// Zeus records the person's microphone whenever it is listening, whoever else uses the input.
    public var recordsMicrophone: Bool { phase == .listening }

    /// Zeus is listening and another app is using the microphone at the same time.
    public var shared: Bool { phase == .listening && otherAppActive }

    public mutating func apply(_ event: Event) -> [Effect] {
        let wasShared = shared
        var effects: [Effect] = []
        switch event {
        case .zeusStarted:
            if phase == .released {
                phase = .listening
                effects.append(.openInput)
            }
        case .zeusStopped:
            if phase == .listening {
                phase = .released
                effects.append(.closeInput)
            }
        case .otherApp(let active):
            otherAppActive = active
        case .defaultInputChanged:
            if phase == .listening { effects.append(.reopenInput) }
        }
        if shared != wasShared { effects.append(.sharedChanged(shared)) }
        return effects
    }
}
