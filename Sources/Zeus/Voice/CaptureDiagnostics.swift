import Foundation

/// What one listening turn's input saw, for the voice log when a turn ends with nothing heard.
/// A headset that never delivered audio shows as zero frames on a named device.
struct CaptureDiagnostics: Equatable, Sendable {
    var deviceName = "unknown input"
    var sampleRate = 0.0
    var channels = 0
    var frames = 0
    var configChanges = 0

    /// For example `nothing heard: AirPods Pro, 24000 Hz 1 ch, 0 frames, 1 config change`.
    var nothingHeardSummary: String {
        let changes = configChanges == 1 ? "1 config change" : "\(configChanges) config changes"
        let rate = sampleRate.isFinite ? Int(sampleRate.rounded()) : 0
        return "nothing heard: \(deviceName), \(rate) Hz \(channels) ch, \(frames) frames, \(changes)"
    }
}
