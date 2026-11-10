import Foundation
import ZeusCore

/// The plug-in point between any dictation engine and the top bar. The notch only reads these
/// values: the hold-to-talk wings, the live waveform and the result cue. The Apple speech
/// controller on this branch writes them today; the Parakeet/Whisper engine on devon/claude
/// plugs in by writing the same four calls, with no top bar change.
@MainActor
protocol DictationDisplay: AnyObject {
    var dictationPhase: TopBarModel.DictationPhase { get set }
    var dictationPartial: String { get set }
    func pushDictationLevel(_ level: Double)
    func show(_ cue: NotchCue)
}

extension TopBarModel: DictationDisplay {}
