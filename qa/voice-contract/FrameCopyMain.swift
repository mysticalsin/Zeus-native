import Foundation

@main
struct FrameCopyMain {
    static func main() async {
        let samples = [Float](repeating: 0.25, count: VoiceFrame.sampleCount)
        let backend = try! FakeDuplexVoiceBackend(frames: [samples, samples])
        _ = try! await backend.start()
        VoiceFrame.constructions = 0
        _ = try! await backend.push(userFrame: samples)
        if VoiceFrame.constructions != 0 {
            fputs("FAIL push constructed \(VoiceFrame.constructions) extra frames\n", stderr)
            exit(1)
        }
        fputs("frame copy ok\n", stderr)
    }
}
