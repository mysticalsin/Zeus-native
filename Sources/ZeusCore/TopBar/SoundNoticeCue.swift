import Foundation

/// How a sound-notice cue is shown in the closed notch.
///
/// The output list composes the line ("Sound moved to Kitchen", "Could not switch to Office").
/// This type only decides the duration, the speaker symbol, that the notice still appears when
/// everyday cues are off, and that the line never becomes a macOS banner or a log of the device name.
public struct SoundNoticeLine: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var line: String

    public init(line: String) {
        self.line = line
    }

    public var description: String { SoundNoticeCue.recordName }

    public var debugDescription: String { SoundNoticeCue.recordName }
}

public enum SoundNoticeCue {
    /// `NotchCue.soundNotice` stays up for 3.5 seconds.
    public static let duration: TimeInterval = 3.5

    /// Drawn beside the line. The view tints it; this type only names the symbol.
    public static let symbol = "speaker.wave.2.fill"

    /// Flight recorder and `String(describing:)`. The case name only, never the line.
    public static let recordName = "soundNotice"

    /// The notice answers an act of the owner, so it joins the essential cues.
    public static let essential = true

    public static func shows(everydayCuesOn: Bool) -> Bool {
        everydayCuesOn || essential
    }

    public static func systemNotificationAllowed(line _: String) -> Bool {
        false
    }

    /// There is no banner form. A device name stays in the notch.
    public static func banner(line _: String) -> String? {
        nil
    }

    public static func notice(line: String) -> SoundNoticeLine {
        SoundNoticeLine(line: line)
    }

    /// The one line the closed notch draws.
    public static func detail(line: String) -> String {
        notice(line: line).line
    }
}
