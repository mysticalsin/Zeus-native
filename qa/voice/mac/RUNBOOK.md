# Mac voice renders

`render_mac.sh` is the Mac entrypoint. It takes one output directory and writes only inside it.

```sh
qa/voice/mac/render_mac.sh /tmp/zeus-voice-mac
```

Linux exits 2 and writes `host-status.txt` in that directory. It does not invent audio.

## say

`say -f` reads the script with the `[[BARGE-IN]]` marker removed, writes an AIFF inside the output directory, and `afconvert` turns it into 16-bit WAV. The timing JSON's `first_audio_s` is the wall clock of those two commands. `say` is the system speech synthesizer. It does not apply Zeus's Ultron effect, rate, or pitch.

Set `SAY_VOICE` to choose a voice, for example `SAY_VOICE=Daniel`. With it unset, `say` uses the Mac's default voice.

## AVSpeechSynthesizer

`render_avspeech.swift` calls `AVSpeechSynthesizer.write`, which is the same entry `SystemVoiceRender.render` uses. Rate and pitch come from `avspeech_plan.py`: 0.92 of `AVSpeechUtteranceDefaultSpeechRate`, and a pitch multiplier of 0.82, matching `UltronSystemVoicePick`. That file also exits 2 when the text is empty. The voice is the first installed voice named Daniel, Alex, or Tom. The Ultron effect chain stays in the app, so this WAV is the raw system render. Linux runs the plan. It does not run `AVSpeechSynthesizer`, because AVFoundation is not on Linux.

The shell runs it only when `swift` is on `PATH`.

## zeus.synthetic

This script does not render `zeus.synthetic`.

On commit `665b9167303f9596d5222b77a663e36f780d60d7` (PR 52), `PersonaSyntheticVoice.voiceID` is `zeus.synthetic` and `PersonaVoiceResolver.resolve` always returns it. `Speaker` does not read that id. No Zeus flag writes these scripts to a WAV.

`Zeus --voice-engine-selftest` speaks one fixed line through whatever engines are already configured. Its default receipt path is `~/AI-Brain-build/voice-selftest/`, outside the output directory, and `--silent` only mutes playback. That command is not a render of this script set, so `render_mac.sh` does not launch it.

`ZEUS_BIN` is recorded in `zeus-synthetic/STATUS.txt` and is not executed. A headless render would have to write the script WAVs inside the output directory and would have to be a path the app already has. This tree does not have one.
