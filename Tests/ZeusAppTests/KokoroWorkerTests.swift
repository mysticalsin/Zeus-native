import Foundation
import Testing
#if ZEUS_PORTABLE_KOKORO
@testable import KokoroValidation
#else
@testable import Zeus
#endif

@Suite struct KokoroWorkerTests {
    @Test func jsonLineEncodingRoundTrip() throws {
        let line = KokoroWorker.Line(text: "Hello", voice: "am_michael", speed: 0.94, out: "/tmp/x.wav")
        let data = try KokoroWorker.encodeLine(line)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"text\":\"Hello\""))
        #expect(json.hasSuffix("\n"))
    }

    @Test func argvPassesModelPathsAsArguments() {
        let dir = URL(fileURLWithPath: "/tmp/kokoro-\"models", isDirectory: true)
        let args = KokoroWorker.argv(python: "/usr/bin/python3", modelDir: dir)
        #expect(Array(args.suffix(2)) == [dir.appendingPathComponent("kokoro-v1.0.onnx").path,
                                        dir.appendingPathComponent("voices-v1.0.bin").path])
        #expect(!args[2].contains(dir.path))
    }

    @Test func derivedPathsMatchHistoricalLiteralsWhenHomeIsOwner() {
        let previous = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", "/Users/example", 1)
        defer {
            if let previous {
                setenv("HOME", previous, 1)
            } else {
                unsetenv("HOME")
            }
        }
        #expect(KokoroWorker.defaultModelDir.path == "/Users/example/AI-Brain-build/jarvis-laya-backend/models")
        #expect(KokoroWorker.jarvisPython.path == "/Users/example/AI-Brain-build/jarvis-laya-backend/.venv/bin/python")
        let now = Date(timeIntervalSince1970: 1_732_156_800)
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "")
        let receipt = VoiceSelfTest.defaultReceiptURL(now: now)
        #expect(receipt.path == "/Users/example/AI-Brain-build/voice-selftest/receipt-\(stamp).json")
    }

    @Test func isSetUpFalseWhenModelMissing() {
        let name = NSTemporaryDirectory() + "zeus.kokoro.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("/tmp/zeus-missing-kokoro-\(UUID().uuidString)", forKey: "voice.kokoro.modelDir")
        #expect(!KokoroWorker.isSetUp(defaults: defaults))
    }
}
