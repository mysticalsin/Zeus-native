import AVFAudio
import Speech
import ZeusCore

/// Audio and speech callbacks that run on a realtime or background thread.
///
/// A tap block or recognition handler written inside a `@MainActor` type inherits main-actor
/// isolation, and Swift 6 traps on the first buffer or result because the system calls it off the
/// main thread (the same failure as the TCC handler fixed in `SystemAuthorization`). These helpers
/// are nonisolated, so the blocks they install carry no actor isolation; results reach the caller on
/// the main actor. A closed-loop source lint keeps `@MainActor` types from installing them directly.
enum OffMainAudioCallbacks {
    /// Installs an input-level tap. `measure` runs on the audio thread; `deliver` runs on the main actor.
    nonisolated static func installLevelTap(on node: AVAudioNode, format: AVAudioFormat,
                                            measure: @escaping @Sendable (UnsafeBufferPointer<Float>) -> Double,
                                            deliver: @escaping @MainActor @Sendable (Double) -> Void) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let value = measure(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            DispatchQueue.main.async { MainActor.assumeIsolated { deliver(value) } }
        }
    }

    /// Runs one recognition and reports it on the main actor.
    /// A final is delivered at once. At the give-up the task is cancelled and the latest
    /// partial is delivered. The text is empty only when no partial arrived.
    nonisolated static func recognizeFinal(_ recognizer: SFSpeechRecognizer, request: SFSpeechRecognitionRequest,
                                           completion: @escaping @MainActor @Sendable (String, String?) -> Void) {
        let gate = STTOnce()
        let heard = STTFileRecognition()
        let task = recognizer.recognitionTask(with: request) { result, error in
            let text = heard.note(text: result?.bestTranscription.formattedString,
                                  isFinal: result?.isFinal == true,
                                  failed: error != nil)
            guard let text else { return }
            let message = text.isEmpty ? error?.localizedDescription : nil
            gate.run {
                DispatchQueue.main.async { MainActor.assumeIsolated { completion(text, message) } }
            }
        }
        let giveUp = STTFileGiveUp.seconds(audioMs: STTFileGiveUp.standInAudioMs)
        DispatchQueue.global().asyncAfter(deadline: .now() + giveUp) {
            let text = heard.giveUp()
            task.cancel()
            guard let text else { return }
            gate.run {
                DispatchQueue.main.async { MainActor.assumeIsolated { completion(text, nil) } }
            }
        }
    }
}
