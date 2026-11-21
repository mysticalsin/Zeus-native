# Spoken style

`SpokenStyle` turns a reply into short spoken runs before any voice provider sees it. It is a pure function in `Sources/ZeusCore/Voice/SpokenStyle`. It does not speak, and it is not called by the speaker yet.

Pauses are `SpokenPause` values (`.clause` or `.sentence`). They are not SSML. Each provider maps the enum onto its own break when that provider is wired.

The pipeline is `SpokenStyle.stages`, in this order: markdown, links, quantities, contractions, clauses, answer first. `SpokenStage.transform` switches on every case and has no default.

## How slice (c) and the speaker will call it

Slice (c) is the reply-preparation step that sits in front of the speaker. Today `VoiceTurnController.say` calls `VoiceTurnController.voiced`, which runs `UltronSpeechText.prepared`, and then `speaker.speak`. This module is not part of that path yet. When slice (c) is wired, it shapes the reply and hands the runs to the speaker:

```swift
// Slice (c): prepare the brain reply. Do this before speaker.speak.
let transcript = SpokenStyle.transform(SpokenRequest(
    text: reply,
    language: .english, // or .french
    maxSentences: 3     // nil keeps every sentence
))

// Speaker: speak each run, then map the pause for that provider.
// SpokenStyle does not emit <break> or any other SSML.
for run in transcript.runs {
    speaker.speak(run.text)
    provider.pause(for: run.pauseAfter)
}
```

`Speaker.speak(_:)` and `Speaker.speak(sentenceStream:)` stay as they are. A later change can pass `run.text` into those entry points and apply `run.pauseAfter` in the provider that actually plays audio. Slice (c) owns the call to `SpokenStyle.transform`. The speaker owns the mapping from `SpokenPause` to a provider pause.
