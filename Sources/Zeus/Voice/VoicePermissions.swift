import AppKit
import AVFoundation
import Speech
import ZeusCore

/// Microphone and speech recognition for voice, asked for only from explicit actions: turning
/// "Listen for Hey Zeus" on, the first talk-key press, and the onboarding voice step. Never at launch. macOS shows each prompt once ever; after a refusal ZEUS shows a
/// notch cue with a button to the right Privacy pane instead of staying silent.
@MainActor
enum VoicePermissions {
    /// Shows the "can't hear you" cue; AppDelegate wires it to the notch.
    static var showDenied: ((String, String) -> Void)?
    private static var asking = false
    private static var lastCueAt = Date.distantPast

    static func state(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static var mic: PermissionState { state(AVCaptureDevice.authorizationStatus(for: .audio)) }
    static var speech: PermissionState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
    static var access: VoiceAccess { VoiceAccess.decide(mic: mic, speech: speech) }

    /// Asks (when allowed for this occasion), then reports. A refusal raises the notch cue, at
    /// most once every 20 s so a held key doesn't spam it.
    @discardableResult
    static func ensure(explicit: Bool) async -> VoiceAccess {
        var current = access
        if current.shouldPrompt(wakeOn: WakeWordController.shared.enabled, explicit: explicit), !asking {
            asking = true
            VoiceLog.log("permission", "asking (mic \(mic), speech \(speech), explicit \(explicit))")
            if mic == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .audio) }
            if speech == .notDetermined {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
                }
            }
            asking = false
            current = access
            VoiceLog.log("permission", "result: mic \(mic), speech \(speech)")
        }
        if let cue = current.deniedCue, let pane = current.deniedPane { notifyDenied(cue, pane) }
        return current
    }

    static func notifyDenied(_ cue: String, _ pane: String) {
        guard Date().timeIntervalSince(lastCueAt) > 20 else { return }
        lastCueAt = Date()
        VoiceLog.log("permission", "denied: \(cue)")
        showDenied?(cue, pane)
    }

    /// For Settings: one line about voice access.
    static var statusLine: String {
        switch access {
        case .ready: "Microphone and speech recognition are allowed."
        case .needsPrompt: "Not asked yet. Turn on Hey Zeus or press the talk key and macOS will ask once."
        case .denied(let mic, let speech):
            "Refused in System Settings: " + [mic ? "Microphone" : nil, speech ? "Speech Recognition" : nil].compactMap { $0 }.joined(separator: " and ") + "."
        }
    }
}
