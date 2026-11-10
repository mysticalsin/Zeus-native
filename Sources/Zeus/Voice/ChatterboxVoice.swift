import Foundation

/// Local Chatterbox Turbo (MLX) voice clone from a reference clip (K3). Model download is manual.
enum ChatterboxVoice {
    static var modelRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zeus/Models/chatterbox-turbo", isDirectory: true)
    }

    static var referenceClip: URL {
        if let custom = UserDefaults.standard.string(forKey: "voice.chatterbox.referencePath"),
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return URL(fileURLWithPath: custom)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zeus/Voices/ultron-ref.wav")
    }

    static var isModelPresent: Bool {
        FileManager.default.fileExists(atPath: modelRoot.appendingPathComponent(".complete").path)
    }

    static var isReady: Bool {
        isModelPresent && FileManager.default.fileExists(atPath: referenceClip.path)
    }

    static func render(_ text: String) async -> URL? {
        guard isReady, !text.isEmpty else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-chatterbox-\(UUID().uuidString).wav")
        let python = LocalPython.python.path
        let script = synthesisScript(modelRoot: modelRoot, reference: referenceClip, text: text, out: out)
        let status = await Task.detached {
            LocalPython.run(python, ["-I", "-c", script])
        }.value
        guard status.status == 0, FileManager.default.fileExists(atPath: out.path) else { return nil }
        return out
    }

    /// Inline Python: uses `chatterbox` MLX package when installed in the Zeus venv.
    static func synthesisScript(modelRoot: URL, reference: URL, text: String, out: URL) -> String {
        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        import sys
        ref = "\(reference.path)"
        out = "\(out.path)"
        model = "\(modelRoot.path)"
        text = "\(escapedText)"
        try:
            from chatterbox import ChatterboxTTS
        except ImportError:
            sys.exit(1)
        try:
            engine = ChatterboxTTS.from_local(model)
            audio, sr = engine.generate(text, audio_prompt_path=ref)
            import soundfile as sf
            sf.write(out, audio, sr)
        except Exception:
            sys.exit(2)
        """
    }
}
