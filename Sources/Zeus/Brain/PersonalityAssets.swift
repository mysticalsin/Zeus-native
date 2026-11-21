import Foundation
import ZeusCore

/// The bundled personality files (Sources/Zeus/Personality, copied into Zeus_Zeus.bundle). Both loads return nil
/// when the file is missing or unreadable, and the callers keep their compiled fallback.
enum PersonalityAssets {
    static func url(_ name: String) -> URL? {
        let relative = "Personality/\(name)"
        let candidates = [ZeusResources.bundle?.resourceURL, Bundle.main.resourceURL].compactMap { $0 }
        return candidates.map { $0.appendingPathComponent(relative) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func document() -> String? {
        url("ULTRON_PERSONALITY.md").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    static func dialogue() -> UltronDialogue? {
        url("ultron_dialogue.json").flatMap { try? Data(contentsOf: $0) }.flatMap(UltronDialogue.decode)
    }

    /// Hands the dialogue asset to the stock-line bank. A missing file leaves the compiled lines in use.
    static func installDialogue() {
        Task.detached(priority: .userInitiated) {
            ZeusVoiceLines.shared.setDialogue(dialogue())
        }
    }
}
