# Voice latency

Owner request (2026-11-11): Zeus talks like Ultron, has a very nice voice and answers as fast as the quickest reference voice assistant. This page is the pipeline, the targets and how to measure them.

## Targets

Measured from the talk key going up to the first audio buffer scheduled for playback (`ttfa` in the log).

| Route | Target (p50) |
|---|---|
| Anthropic or OpenAI key plus ElevenLabs or OpenAI voice | 1.2 s or less |
| CLI brains only (Claude CLI, Codex CLI), any voice | 2.5 s or less |

Reference: the comparison app waits for the whole model answer, then fetches a whole mp3. Zeus starts the voice on the first sentence while the model is still writing.

## The turn, stage by stage

1. Talk key down. `KeyDownWarmer` opens the TLS and HTTP/2 connection of the brain that will answer (free metadata call) or starts the lean persistent `claude` process when there is no API key. `Speaker.prewarm` does the same for the cloud voice. Nothing warms at launch.
2. Key up (`key_up`, time zero). The transcript is finalised (`transcript`).
3. Request sent (`request`). Every fast engine starts at once; the first to stream text wins, the others stop. A deep answer can follow behind.
4. First token (`first_token`). Text streams through the tag parser and `SentenceSplitter`.
5. First sentence complete (`first_sentence`), or the first 12 complete words of a long first sentence with no comma.
6. TTS request (`tts_request`). Sentence N+1 is requested while sentence N plays; one player node keeps them in order and gapless. A 4 ms fade is applied at a sentence edge only where that edge is not already near zero.
7. First audio (`first_audio`). Turn end (`turn_end`) when the speaker goes quiet.

A new key press, Esc or Stop Speaking cancels generation (the persistent CLI process is stopped), the TTS fetches and playback at once.

## Route matrix

| Saved | Brain | Model | Voice |
|---|---|---|---|
| Anthropic key | direct Messages API stream, one warm session | `claude-haiku-5-5` (thinking off, low effort, cached system block); deep answer `claude-sonnet-4-5` | see voice rows |
| OpenAI key only | direct chat stream | `gpt-4o-mini` (override `modelCap.http.openAI.fast`) | |
| No API key, Claude CLI | persistent lean `claude -p` stream-json process (`--safe-mode`, no tools, no MCP), recycled after 5 turns | `haiku` | |
| No API key, Codex only | Codex CLI one shot | account model, low effort | |
| ElevenLabs key | | | `eleven_flash_v2_5` (Fastest, default) or the Studio model; 24 kHz PCM; the designed Zeus voice once created |
| OpenAI TTS key, no ElevenLabs | | | `gpt-4o-mini-tts`, voice `onyx`, tone instructions, PCM |
| Kokoro ready | | | local deep voice |
| nothing | | | best installed Mac voice (Premium, then Enhanced, then default), deep male preferred, never Samantha, through the Ultron effect; language of the reply picks the voice |

The log line says which engine and model spoke and why.

## Measure it

```sh
bash scripts/voice-latency.sh            # watch live, hold the talk key, Ctrl-C prints p50 and p90
bash scripts/voice-latency.sh --replay   # the turns already in the log
bash scripts/voice-latency.sh --file ~/Library/Logs/Zeus/voice.log.old
```

The script launches nothing. If Zeus is not running it prints how to start it. Each turn writes one line, also visible with `log stream --predicate 'eventMessage CONTAINS "[ZEUS] voice-latency"'`:

```
[ZEUS] voice-latency turn=ab12cd34 key_up=0 transcript=310 request=330 first_token=780 first_sentence=1050 tts_request=1060 first_audio=1420 turn_end=4800 ttfa=1420 brain=anthropic-api model=claude-haiku-5-5 tts=elevenlabs/eleven_flash_v2_5 voice=elevenlabs-direct:... effect=60 reason="..."
```

No transcript text, answer text or key is ever logged. Settings > Voice > Test voice speaks a line in English and French and shows time to first audio, engine, model and voice.

## Keys for the best result

Anthropic API key (`assistant.key.anthropic`) for the 1.2 s route, and an ElevenLabs key for the voice (Settings > Voice, top row). Create the Zeus voice with the one-tap button once the key works.

## Verified and not verified

Verified from documentation text: ElevenLabs model list (`eleven_flash_v2_5` fastest, `eleven_v4` highest quality and expressive), PCM output formats (`pcm_44100` needs Pro; tier rules for other rates are not stated, so 24 kHz is used), `optimize_streaming_latency` is deprecated but still accepted.

Not verified: that `eleven_v4` accepts the streaming endpoint (the Studio option falls back to the fast model for the whole answer if refused), the Spoken Content settings pane anchor, `claude-haiku-5-5` request fields on this account (the request retries plain forms), and the OpenAI fastest model name.
