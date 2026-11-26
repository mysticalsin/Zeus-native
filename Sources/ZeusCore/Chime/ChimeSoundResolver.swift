import Foundation

/// Where a chime's samples come from. A chosen file wins only when it can be read.
/// Otherwise Zeus uses the tone it synthesizes itself.
public struct ChimeResolution: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case customFile(path: String)
        case synthesizedDefault
    }

    public var source: Source
    public var fellBack: Bool
    /// A short note for a private log. It names the event, not the file path.
    public var privateLog: String?

    public init(source: Source, fellBack: Bool, privateLog: String?) {
        self.source = source
        self.fellBack = fellBack
        self.privateLog = privateLog
    }
}

public enum ChimeSoundResolver {
    /// Custom file, then the synthesized default. An empty path is the default, not a failure.
    public static func resolve(event: ChimeEvent, path: String?, readable: Bool) -> ChimeResolution {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return ChimeResolution(source: .synthesizedDefault, fellBack: false, privateLog: nil)
        }
        guard readable else {
            return ChimeResolution(
                source: .synthesizedDefault,
                fellBack: true,
                privateLog: "\(event.rawValue) chime file is missing or unreadable. Using the built-in chime.")
        }
        return ChimeResolution(source: .customFile(path: trimmed), fellBack: false, privateLog: nil)
    }
}
