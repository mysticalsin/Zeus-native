import Foundation

/// Resolves audio paths for `zeus debug dictate-file` and `wake-file` (R24).
public enum DebugAudioPath {
    public static func resolve(_ path: String, workingDirectory: String = FileManager.default.currentDirectoryPath) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.hasPrefix("/") { return trimmed }
        return URL(fileURLWithPath: workingDirectory, isDirectory: true)
            .appendingPathComponent(trimmed)
            .standardizedFileURL
            .path
    }
}
