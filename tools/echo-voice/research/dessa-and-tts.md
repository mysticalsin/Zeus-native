# Block's Dessa, and Mac-local TTS options (Echo, 2026-11-20 15:34–16:00 BRT)

This is read-only research. Nothing was cloned, installed or downloaded (no weights). Facts below come with their links; anything not found is marked **unknown**.
Tony's constraints for this round: Apple **M5, 32 GB, macOS 27.2**; Mac only; no GPU spend; no voice reference for now; Zeus first; he wants **both** TTS and two-way conversation.

## 1. Block's Dessa
| Question | Answer | Source |
|---|---|---|
| What it is | A full-duplex **speech-to-speech** model: "Audio in, audio out". It listens and talks at the same time, backchannels ("yeah!", "got it!"), cuts in, laughs mid-sentence, and hears and speaks emotion | [block.xyz/dessa](https://block.xyz/dessa) |
| What makes it natural (Block's claims) | Trained **from scratch on human conversation audio only**: "No text, no pretrained models." So it learns pauses, breathing, sarcasm, inflection and turn-taking from raw speech. It was trained on one NVIDIA GB200 NVL72 | same page |
| Weights / code / API | **None released.** It is a research preview with early access for a small group of AI-safety researchers and a contact address. GitHub `dessa org:block` returns 0 repos (I checked the GitHub API today). An HF search for "dessa" returns only unrelated or unofficial uploads | page; [GitHub search API](https://api.github.com/search/repositories?q=dessa+org:block); [HF search](https://huggingface.co/api/models?search=dessa) |
| Licence | **None published** | page; corroborated by [SingularityByte](https://singularitybyte.com/news/block-dessa-open-full-duplex-speech-models.html), a third party |
| Architecture, size, codec | **Unknown.** No parameter count, codec, paper or model card | page |
| Hardware | "runs locally on a MacBook Pro M4 Max or better"; "Inference runs faster than real time" | page |
| Runs on an M5 with 32 GB? | **Unknown.** Block names "M4 Max or better", and we can't tell whether an M5 with 32 GB qualifies. It is moot until weights exist | — |
| Naturalness / latency numbers | **None published.** There are only curated recordings and no benchmark (e.g. no Full-Duplex-Bench) | page; SingularityByte |
| Text-to-speech? | **No.** It is speech-to-speech only and has no text input mode described | page |
| Unofficial "Dessa" uploads | Treat as untrusted (e.g. `larslavrone/dessa-rvc` on HF is not Block's) | HF search |

**Verdict:** Dessa is the *quality reference* for "natural", but it is **not a usable base**: no weights, no licence and no TTS mode. For two-way conversation on the Mac, Haru-4B is the available open model of the same kind (Apache-2.0, MLX path). It published 43 ms/frame in bf16 with a 13.5 GB peak on an M1 Max ([tests README](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru_mlx/tests/README.md)), which fits in 32 GB. For reading text aloud, neither Haru nor Dessa works; a TTS engine is needed (section 2).

## 2. Mac-local TTS options (FR + EN, free, licence-compatible)
"Bundled voices" below means preset voices shipped by the project. Several of them are **recordings of real, consenting or dataset-licensed speakers**, not synthetic voices; licences per voice are flagged. We do **no cloning** from our own clips.

| Engine | Licence (code / weights) | FR? | Size | Mac / Rust / MLX path | Published speed | Notes |
|---|---|---|---|---|---|---|
| **Kokoro-82M v1.0** ([card](https://huggingface.co/hexgrad/Kokoro-82M)) | Apache-2.0 / Apache-2.0 | Yes, but thin: **1 female voice `ff_siwis`, grade B-, <11 h of French data**, trained on SIWIS (CC BY 4.0) ([VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md)) | 82 M params | **Already in Zeus** via a kokoro-onnx Python worker. Rust: [Kokoros](https://github.com/lucasjinreal/Kokoros) (Apache-2.0). MLX: [mlx-community/Kokoro-82M-bf16](https://huggingface.co/mlx-community/Kokoro-82M-bf16) | No first-party latency figure | StyleTTS2 + ISTFTNet; weak on short utterances (per VOICES.md). There is **no French male voice**, which conflicts with Zeus's deep-male persona |
| **Kyutai Pocket TTS** ([repo](https://github.com/kyutai-labs/pocket-tts), MIT code; weights [kyutai/pocket-tts](https://huggingface.co/kyutai/pocket-tts) CC-BY-4.0, **HF gated "auto"**: you accept terms with an HF login) | MIT / CC-BY-4.0 | **Yes** (en, fr, de, pt, it, es, nl); French voice "estelle" | ~100 M params (English variants down to 1.9 M) | **Official Rust binary for macOS ARM** in releases (v4.0.1, 2026-10-21, `aarch64-apple-darwin` 7.7 MB). It runs on CPU with no Python. Community MLX and Candle ports exist | "~200ms to get the first audio chunk", "~6x real-time on a CPU of MacBook Air M4", 2 CPU cores (README) | Supports voice cloning; **we use catalog voices only**. Voice licences vary by voice ([tts-voices](https://huggingface.co/kyutai/tts-voices)): VCTK CC-BY-4.0, voice-donations CC0, **Expresso and EARS are non-commercial**. Avoid NC voices and the `degaulle` clip |
| **Kyutai TTS 1.6B en_fr** ([card](https://huggingface.co/kyutai/tts-1.6b-en_fr)) | MIT (Python) + Apache (Rust) code / **CC-BY-4.0** weights | **Yes**, built for EN+FR | 1.8 B actual params; repo 4.07 GB | **MLX** (`moshi-mlx`, `scripts/tts_mlx.py --quantize 8/4`), Rust server (`moshi-server`, CUDA-oriented), Swift via [moshi-swift](https://github.com/kyutai-labs/moshi-swift) (MIT) ([DSM repo](https://github.com/kyutai-labs/delayed-streams-modeling)) | Paper ([arXiv 2509.08753](https://arxiv.org/abs/2509.08753)) Table 6: 150 ms latency, RTF 3.2 at batch 1 (H100 implied, not Mac). **Mac speed unknown** | Streams text in → audio out (good for Zeus's sentence stream). Paper Table 5, **French** MUSHRA quality: DSM-TTS 62.5 ± 2.0 vs ElevenLabs Multilingual v2 66.4 ± 2.0 and Flash 61.5 ± 2.3; English 54.8 vs Chatterbox 67.7. Voices only via precomputed embeddings; French voices from CML-TTS (CC-BY-4.0) |
| **Chatterbox** (Turbo 350M EN; Multilingual V3 500M, 23 languages incl. fr) ([repo](https://github.com/resemble-ai/chatterbox)) | MIT / MIT | Multilingual V3: yes | 0.35–0.5 B | Already in Zeus ("Local Chatterbox Turbo", used only when chosen). No first-party MLX or Rust | Paper Table 6: RTF 1.8 (H100). Mac speed unknown | **Clone-from-reference by design** (an `audio_prompt_path`), which conflicts with "no reference". Perth watermark on every output. The repo now says it is an **unsupported archive** |
| Sesame CSM-1B ([card](https://huggingface.co/sesame/csm-1b)) | Apache-2.0 | **No** (en only) | 1.55 B | — | RTF 1.0 (paper Table 6) | English only, so it fails the FR requirement |
| Dia-1.6B ([card](https://huggingface.co/nari-labs/Dia-1.6B)) | Apache-2.0 | Card says en; paper scored FR quality at 24.9 | 1.6 B | — | RTF 0.7 | Poor French per paper Table 5 |
| Orpheus 3B ([card](https://huggingface.co/canopylabs/orpheus-3b-0.1-ft)) | Apache-2.0 | French "research release" only ([3b-fr](https://huggingface.co/canopylabs/3b-fr-ft-research_release)) | 3.3–3.8 B | — | RTF 0.7 | Slowest, and English quality is lowest in Table 5 |
| F5-TTS ([card](https://huggingface.co/SWivid/F5-TTS)) | **CC-BY-NC-4.0** weights | — | — | — | — | **Excluded: non-commercial** |
| macOS system voices (`AVSpeechSynthesizer`) | Apple OS licence | Yes | 0 download | Already Zeus's last-resort engine | — | The quality floor; Zeus already prefers Premium/Enhanced voices |

### Recommendation for "reads text aloud" (FR+EN, Mac-local, free)
1. **Kyutai Pocket TTS (Rust binary, CPU)** as the first new local engine in Zeus.
   - It is the only option with an **official native macOS ARM binary**, needs **no Python**, and covers French.
   - Its published figures are ~200 ms to the first chunk and ~6× real-time on an M4 Air.
   - It fits Tony's "Rust in place of Python" goal at no cost, and it frees the GPU for Haru.
   - Open points: an HF-gated licence acceptance is needed, and voice licences must be checked per voice.
2. **Kyutai TTS 1.6B en_fr via MLX** as the quality candidate. It has the best published French result among the open models here (62.5 MUSHRA vs ElevenLabs Flash 61.5), and it streams. Its speed on Mac is unknown, so benchmark it on the M5.
3. Keep Kokoro as the English failsafe Zeus already ships. Its French is a single B- female voice.

### For "two-way conversation"
Haru-4B via `haru_mlx`, bench first (see `haru-research.md`). It needs about 13.5 GB in bf16 out of the 32 GB. If Zeus's TTS engine is also resident, they'll share memory: Pocket TTS is about 100 M params on CPU, and Kyutai 1.6B is about 4 GB. Dessa is the target feel, but it can't be used today.

## 3. Unknowns
- Whether Dessa will ever be released, and under what licence or size.
- Speeds on the M5 for every engine (none are published for M5).
- Haru's default voice when no reference is given. The code uses no reference, so it is the model's prior; quality is unknown.
- Pocket TTS gating terms: the README part that spells them out didn't load (fetch timed out). Read the HF terms before accepting.
- Kyutai 1.6B MLX real-time factor on an M-series Mac.
