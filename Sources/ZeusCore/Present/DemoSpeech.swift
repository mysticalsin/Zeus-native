import Foundation

/// One step of Play Demo that can hand a line to the existing voice.
/// The menu-bar point used to show a label and stay silent.
public enum DemoStep: String, Sendable, Equatable {
    /// The spark points at Zeus's own menu-bar icon.
    case menuBarPoint
}

/// The line Play Demo hands to the existing Zeus voice. A nil line is a silent step.
public enum DemoSpeech {
    /// The words for this step, or nil while the step only moves the spark.
    public static func line(for step: DemoStep) -> String? {
        switch step {
        case .menuBarPoint:
            return nil
        }
    }

    /// Speaks one demo step through the caller's voice. Returns the line, or nil when the step stays silent.
    public static func speak(_ step: DemoStep, using say: (String) -> Void) -> String? {
        guard let line = line(for: step)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else {
            return nil
        }
        say(line)
        return line
    }
}
