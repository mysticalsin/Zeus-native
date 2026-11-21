import Foundation

/// Holds the WAV URL across the main-actor render hop. The background caller reads it after the signal.
final class KokoroRenderBox: @unchecked Sendable {
    var url: URL?
}

/// Blocking Kokoro waits. `speakKokoro` calls these from a global queue, never from the main actor:
/// the render waits for the worker, and playback hops back to the main queue to schedule.
enum KokoroClauseWait {
    static func scheduleOnMain(_ body: () -> Bool) -> Bool {
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                body()
            }
        }
    }

    static func render(_ text: String, voice: String, speed: Double, began: Date, token: SpeechCancelToken) -> URL? {
        let box = KokoroRenderBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            if Task.isCancelled { token.cancel() }
            box.url = await KokoroVoice.render(text, voice: voice, speed: speed)
            // The same first-audio budget covers every clause, not only the one before playback starts.
            if token.isCancelled || (box.url != nil && Date().timeIntervalSince(began) > VoiceTTSChain.firstAudioTimeout + 30) {
                if let url = box.url { try? FileManager.default.removeItem(at: url) }
                box.url = nil
                token.cancel()
            }
            semaphore.signal()
        }
        semaphore.wait()
        return box.url
    }
}
