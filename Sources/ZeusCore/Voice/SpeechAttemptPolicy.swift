/// When a spoken line that produced no audio counts against the engine, and when its late audio may still play.
///
/// Pressing the talk key or Esc cancels the speaking task while an engine is mid-request. That engine then returns
/// "no audio" like a broken one, and recording it would pause a healthy ElevenLabs, OpenAI or Kokoro route after every
/// barge-in. Audio that finishes rendering after the cancel must not be scheduled either, or the old answer talks over
/// the new question.
public enum SpeechAttemptPolicy {
    /// Record the failure (and maybe pause the route) only for a line nobody interrupted.
    public static func shouldRecordFailure(producedAudio: Bool, cancelled: Bool) -> Bool {
        !producedAudio && !cancelled
    }

    /// Rendered audio may be scheduled only while the speaking task is still wanted.
    public static func mayPlay(cancelled: Bool) -> Bool { !cancelled }
}
