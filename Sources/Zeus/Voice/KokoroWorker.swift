import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Resident Kokoro-onnx worker (PLAN-QA7 §2). One Python process, JSON lines on stdin.
enum KokoroWorker {
    struct Line: Codable, Equatable {
        var id: String = UUID().uuidString
        var text: String
        var voice: String
        var speed: Double
        var out: String
    }

    static let defaultModelDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("AI-Brain-build/jarvis-laya-backend/models", isDirectory: true)
    static let jarvisPython = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("AI-Brain-build/jarvis-laya-backend/.venv/bin/python")

    static func modelDir(from defaults: UserDefaults = .standard) -> URL {
        if let path = defaults.string(forKey: "voice.kokoro.modelDir"), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultModelDir
    }

    static func pythonExecutable() -> String {
        let jarvis = jarvisPython.path
        if FileManager.default.isExecutableFile(atPath: jarvis),
           LocalPython.run(jarvis, ["-I", "-c", "import kokoro_onnx"], timeout: 10).status == 0 {
            return jarvis
        }
        return LocalPython.python.path
    }

    static func modelFiles(in dir: URL) -> (onnx: URL, voices: URL) {
        (dir.appendingPathComponent("kokoro-v1.0.onnx"), dir.appendingPathComponent("voices-v1.0.bin"))
    }

    nonisolated(unsafe) private static var importProbePassed: Bool?
    private static let probeLock = NSLock()

    static func kokoroOnnxImportWorks(python: String = pythonExecutable()) -> Bool {
        probeLock.lock()
        defer { probeLock.unlock() }
        if let cached = importProbePassed { return cached }
        let ok = FileManager.default.isExecutableFile(atPath: python)
            && LocalPython.run(python, ["-I", "-c", "import kokoro_onnx"], timeout: 10).status == 0
        importProbePassed = ok
        return ok
    }

    /// Forgets the cached import answer, so a fresh install is noticed without a relaunch.
    static func resetImportProbe() {
        probeLock.lock()
        defer { probeLock.unlock() }
        importProbePassed = nil
    }

    /// The model and voices files exist. A file check only: cheap enough for the main thread.
    static func modelFilesPresent(defaults: UserDefaults = .standard) -> Bool {
        let files = modelFiles(in: modelDir(from: defaults))
        return FileManager.default.fileExists(atPath: files.onnx.path)
            && FileManager.default.fileExists(atPath: files.voices.path)
    }

    /// Files present and the Python import works. The import probe is slow: call this off the main thread.
    static func isSetUp(defaults: UserDefaults = .standard) -> Bool {
        guard modelFilesPresent(defaults: defaults) else { return false }
        return kokoroOnnxImportWorks()
    }

    /// The Python packages the worker script imports. Setup installs exactly these.
    static let pythonPackages = ["kokoro-onnx", "soundfile", "numpy"]

    /// Where Setup puts the model files when none are on this Mac yet.
    static var managedModelDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zeus/Kokoro", isDirectory: true)
    }

    struct ModelSource: Sendable {
        let name: String
        let url: String
        /// Smaller than this means a cut-off or error page, not the model.
        let minBytes: Int64
    }

    /// The published kokoro-onnx v1.0 files, fetched only when the person presses Set up.
    static let modelSources = [
        ModelSource(name: "kokoro-v1.0.onnx", url: "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx", minBytes: 100_000_000),
        ModelSource(name: "voices-v1.0.bin", url: "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin", minBytes: 5_000_000),
    ]

    private static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Downloads whichever model file is missing or too small into `dir`; nil on success, else what went wrong.
    static func downloadModelFiles(to dir: URL) async -> String? {
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            return "Could not create \(dir.path): \(error.localizedDescription)"
        }
        for source in modelSources {
            let target = dir.appendingPathComponent(source.name)
            if fileSize(target) >= source.minBytes { continue }
            guard let url = URL(string: source.url) else { return "Bad address for \(source.name)." }
            do {
                let (temp, response) = try await URLSession.shared.download(from: url)
                defer { try? FileManager.default.removeItem(at: temp) }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200 else { return "Downloading \(source.name) failed: the server answered \(code)." }
                guard fileSize(temp) >= source.minBytes else { return "Downloading \(source.name) stopped early. Try again." }
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: temp, to: target)
            } catch {
                return "Could not download \(source.name): \(error.localizedDescription)"
            }
        }
        return nil
    }

    /// Whether the package loads the two files in `modelDir`. Slow: call off the main thread.
    static func modelLoads(python: String, modelDir: URL) -> Bool {
        let files = modelFiles(in: modelDir)
        let script = "import sys\nfrom kokoro_onnx import Kokoro\nKokoro(sys.argv[1], sys.argv[2])"
        return LocalPython.run(python, ["-I", "-c", script, files.onnx.path, files.voices.path]).status == 0
    }

    static func workerScript(modelDir: URL) -> String {
        """
        import sys, json, os, contextlib
        os.umask(0o077)
        with contextlib.redirect_stdout(sys.stderr):
            import soundfile as sf
            from kokoro_onnx import Kokoro
            engine = Kokoro(sys.argv[1], sys.argv[2])
        for line in sys.stdin:
            req = json.loads(line)
            temporary = req["out"] + ".partial"
            ok = False
            try:
                with contextlib.redirect_stdout(sys.stderr):
                    audio, sr = engine.create(req["text"], voice=req["voice"], speed=float(req["speed"]), lang="en-us")
                    sf.write(temporary, audio, sr, format="WAV")
                os.replace(temporary, req["out"])
                ok = True
            except Exception:
                try: os.unlink(temporary)
                except OSError: pass
            print(json.dumps({"id": req["id"], "out": req["out"], "ok": ok}), flush=True)
        """
    }

    static func encodeLine(_ line: Line) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(line) + Data([0x0A])
    }

    static func argv(python: String, modelDir: URL) -> [String] {
        ["-I", "-c", workerScript(modelDir: modelDir), modelFiles(in: modelDir).onnx.path, modelFiles(in: modelDir).voices.path]
    }
}
