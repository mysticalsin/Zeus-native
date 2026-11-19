import Foundation
import ZeusCore

/// Settings for the Ultron persona effect. The audio chain itself is `UltronAudioChain`; the numbers
/// behind each intensity are `UltronEffectParameters`. Applies to every engine, the Mac voice included.
enum UltronVoiceEffect {
    static let enabledKey = "voice.ultronEffect"
    static let intensityKey = "voice.ultronEffect.intensity"

    /// Off on a fresh install: the approved base voice is the clean take C read. A saved choice wins.
    static func enabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? false
    }

    /// 0 to 1. When the effect is turned on, untouched installs get the designed 75 %.
    static func intensity(_ defaults: UserDefaults = .standard) -> Float {
        defaults.object(forKey: intensityKey) as? Float ?? Float(UltronEffectParameters.defaultPercent) / 100
    }

    static var enabled: Bool {
        get { enabled(.standard) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var intensity: Float {
        get { intensity(.standard) }
        set { UserDefaults.standard.set(newValue, forKey: intensityKey) }
    }

    static func parameters(_ defaults: UserDefaults = .standard) -> UltronEffectParameters {
        enabled(defaults) ? .make(percent: UltronEffectParameters.percent(fromIntensity: intensity(defaults))) : .neutral
    }

    static var parameters: UltronEffectParameters { parameters(.standard) }

    static func isNonSilent(_ samples: [Float]) -> Bool {
        samples.contains { abs($0) > 0.001 }
    }
}
