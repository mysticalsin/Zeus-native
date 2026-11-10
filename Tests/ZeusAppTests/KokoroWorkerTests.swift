import Foundation
import Testing
@testable import Zeus

@Suite struct KokoroWorkerTests {
    @Test func jsonLineEncodingRoundTrip() throws {
        let line = KokoroWorker.Line(text: "Hello", voice: "am_michael", speed: 0.94, out: "/tmp/x.wav")
        let data = try KokoroWorker.encodeLine(line)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"text\":\"Hello\""))
        #expect(json.hasSuffix("\n"))
    }

    @Test func argvUsesModelDirInScript() {
        let dir = URL(fileURLWithPath: "/tmp/kokoro-models", isDirectory: true)
        let args = KokoroWorker.argv(python: "/usr/bin/python3", modelDir: dir)
        #expect(args.contains(where: { $0.contains("kokoro-v1.0.onnx") }))
    }

    @Test func isSetUpFalseWhenModelMissing() {
        let defaults = UserDefaults(suiteName: "zeus.kokoro.\(UUID().uuidString)")!
        defaults.set("/tmp/zeus-missing-kokoro-\(UUID().uuidString)", forKey: "voice.kokoro.modelDir")
        #expect(!KokoroWorker.isSetUp(defaults: defaults))
    }
}
