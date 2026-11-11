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

    @Test func isSetUpFalseWhenModelMissing() {
        let name = "zeus.kokoro.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("/tmp/zeus-missing-kokoro-\(UUID().uuidString)", forKey: "voice.kokoro.modelDir")
        #expect(!KokoroWorker.isSetUp(defaults: defaults))
    }
}
