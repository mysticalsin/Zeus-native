# Third-party notices

ZEUS ships or downloads the following third-party work. Attribution lives here and in About,
never in the product UI.

## Qwen 2.5 (last-resort fallback through Ollama, optional, not bundled)
- qwen2.5:7b by the Qwen team, Alibaba Cloud, Apache License 2.0, run only through a separately
  installed Ollama and only when Jev gave no answer.

## Jev (TypeSafe System One API)
- Cloud service at api.typesafe.ai, used under TypeSafe's terms with the owner's own key. No
  TypeSafe code or weights are included. Not used: openjev, typesafe-inc/JEV-27B-Desktop,
  TypeSafeAI/Open-Jev.

## Speech to text (Murmure dictation and voice turns)
Every engine below is optional. Local models are downloaded only when the person clicks Download
in Settings › Murmure; cloud engines run only when chosen and only with the person's own key.

### FluidAudio (Parakeet engines on the Neural Engine)
- Code: https://github.com/FluidInference/FluidAudio, Apache License 2.0 (Swift package, 0.18.x).
- Parakeet TDT 0.6B v3: weights https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3, CoreML
  conversion https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml, CC-BY-4.0
  (attribution: NVIDIA). Downloaded on request.
- Parakeet Ultra: weights https://huggingface.co/moondream/parakeet-ultra (Moondream's
  post-training of NVIDIA Parakeet TDT 0.6B v3), CoreML conversion
  https://huggingface.co/FluidInference/parakeet-ultra-coreml, CC-BY-4.0 (attribution: NVIDIA,
  Moondream). Downloaded on request.

### Whisper (OpenAI model weights, MIT)
- Whisper model weights: https://github.com/openai/whisper, MIT License.
- whisper.cpp: https://github.com/ggml-org/whisper.cpp, MIT License. Used through a separately
  installed `whisper-cli` (Homebrew); ggml weights from https://huggingface.co/ggerganov/whisper.cpp
  (MIT), downloaded on request.
- WhisperKit (Argmax): https://github.com/argmaxinc/argmax-oss-swift, MIT License. Compiled in
  (Swift package argmax-oss-swift 1.1.1, product WhisperKit; swift-argument-parser 1.8.2 is also
  pinned in Package.resolved and its license is included below). No swift-transformers package
  pin appears in this project's Package.resolved; no version or license is asserted for it here.
  CoreML weights https://huggingface.co/argmaxinc/whisperkit-coreml
  (openai_whisper-large-v3-v20240930_turbo_632MB), MIT. Downloaded on request.
- faster-whisper: https://github.com/SYSTRAN/faster-whisper, MIT License, installed on request
  into a private Python environment with its dependencies (CTranslate2, MIT); its CTranslate2
  Whisper weights come from Hugging Face (Systran, MIT).

### Apple
- Apple Speech framework (SFSpeechRecognizer, SpeechAnalyzer/SpeechTranscriber): part of macOS;
  language assets are installed and managed by macOS.

### Cloud services (no code or weights included; the person's own key and account terms)
- ElevenLabs Scribe v2 Realtime (`scribe_v2_realtime`), https://elevenlabs.io, ElevenLabs terms.
- OpenAI `gpt-transcribe`, https://platform.openai.com, OpenAI terms.

## Text to speech (Settings › Voice, optional)
### Kokoro (hexgrad/kokoro-onnx)
- kokoro-onnx: Apache License 2.0. Model weights from Hugging Face, fetched only when set up.

### Chatterbox Turbo (Resemble AI, MLX)
- Chatterbox Turbo: MIT License. Outputs may carry an inaudible Resemble watermark. Model
  downloaded manually into Application Support; not bundled.

### Qwen3-TTS VoiceDesign (reference clip generation)
- Qwen3-TTS: Apache License 2.0. Used only to synthesize an original Ultron-style reference clip
  locally; no film or actor audio is cloned.

### Cloud TTS (person's own key)
- ElevenLabs voice library, ElevenLabs terms.
- OpenAI-compatible `/v1/audio/speech` endpoints, provider terms.

### Considered and not shipped
- Cohere Transcribe 03-2026 (FluidAudio has a CoreML port): its model card lists CC-BY-NC-4.0
  (non-commercial) while the repo metadata says Apache 2.0. Not offered until that is settled.
- Parakeet realtime EOU 120M (NVIDIA Open Model License): English only and emits lowercase text
  without punctuation, so not a dictation engine.

## Sounds (Sources/Zeus/Sounds)
- Original to Zeus, no third-party audio. Every file is synthesized from sine partials by scripts in
  this repo, Python standard library only: `tools/sounds/make_sounds.py` (the AAC set) and
  `scripts/gen-dictation-sounds.py` (the Crystal dictation cues `dictation_crystal_start.wav`,
  `dictation_crystal_stop.wav` and `dictation_cancel.wav`, deterministic, rerun to reproduce them).
  Nothing is sampled, downloaded or extracted from another app.

## Polyglot (Tony's own project)

Zeus's Polyglot tab reuses design ideas from Tony's Polyglot (README.md and DESIGN.md): the
microphone / system audio / both source model, the caption card with a language tag, a translation line and a smaller original line,
the edge caption strip that stays on top and is hidden from screen capture, and the filter for captions invented from silence.
The engine here is native (Zeus's speech engines, NaturalLanguage and Apple's Translation framework). Polyglot's Swift sources
were not present in that folder, so no code was copied.

## Engine logos (Chat agent rows, Settings › Integrations)

Marks identify which AI engine a session uses (nominative use only; each mark belongs to its owner).

### Simple Icons (CC0 1.0)
Simple Icons source files are provided under CC0-1.0. Brand names and trademarks
remain the property of their owners; this does not imply provider endorsement.

- Existing OpenAI mark: Simple Icons **15.0.0**,
  https://cdn.jsdelivr.net/npm/simple-icons@15.0.0/icons/openai.svg.
  Used as the OpenAI provider identity for ChatGPT, Codex and GPT models.
  SHA-256: `2b4a04ddc2395b20d168694d3850ce2050a702c4a0cdeb4d8b31b9a970481a8c`.
- Existing Cursor, Claude, Anthropic, Google Gemini, Kimi and Moonshot AI sources:
  Simple Icons **16.36.0**, https://github.com/simple-icons/simple-icons.
  The files originally retrieved on 2026-11-03 were compared byte-for-byte with
  those pinned package versions on 2026-11-10.
- Ollama: Simple Icons **16.36.0**, retrieved 2026-11-10,
  https://cdn.jsdelivr.net/npm/simple-icons@16.36.0/icons/ollama.svg.
  SHA-256: `9c62bf0159ee96c8b58c86a732f33b002b4b3bb165ec86e8ecca51ad6a82dab6`.
- LM Studio: Simple Icons **16.36.0**, retrieved 2026-11-10,
  https://cdn.jsdelivr.net/npm/simple-icons@16.36.0/icons/lmstudio.svg.
  SHA-256: `16e14708a6ecd687e33700b6e9d47e2e60800407d7f995610871603ddbe3816c`.

Original SVGs and exact provenance are in `Design/brand-logos-src/`. Existing
marks use template PDFs; the new Ollama and LM Studio marks retain original SVG
bytes under `Sources/Zeus/Integrations/Brands/`. Mapping is centralized in
`Sources/ZeusCore/Integrations/EngineBrand.swift`.

### Grok / xAI (official original SVG; proprietary trademark)

- Source: https://x.ai/legal/brand-guidelines, corroborated by https://x.ai/grok.
- Retrieved 2026-11-10. The identical inline Grok SVG appears in the official footer's
  “Built with Grok” link on both pages. It was copied byte-for-byte, without redrawing or editing.
- Original and bundled source: `Design/brand-logos-src/grok.svg` and
  `Sources/Zeus/Integrations/Brands/engine-grok.svg`.
- SHA-256: `8157a9b2e3ff94a690000ee9327156eb28539efe176fcb06cadcc7688fb4df90`.
- The original 34×32 dimensions, paths and `currentColor` attributes are retained. The native
  view preserves proportions and uses the label color for the original mark's template rendering.
  Exact retrieval and page hashes are recorded in `Design/brand-logos-src/grok.provenance.json`.

The published guidelines allow accurate references to the provider or services and prohibit
misrepresenting a relationship or implying endorsement, approval or sponsorship. The logo section
also requires logos exactly as supplied at its download link, without alteration or adjustment.
That ZIP link returned HTTP 403 during review; this asset is the verified official inline SVG,
not a claimed copy of the inaccessible ZIP. No correspondence to that pack is asserted.

This proprietary mark is not covered by Simple Icons' CC0 license. Zeus uses it solely to identify
Grok / xAI as the selected provider; no endorsement or broader trademark permission is claimed.

The five unused PNG files formerly named `chatgpt.png`, `claude.png`, `cursor.png`, `gemini.png`
and `grok.png` had unknown individual provenance and have been removed from this source/resource
directory. They are not distributed with the native app.

**Trademark:** All third-party marks remain the property of their owners. Zeus uses them only to
identify the corresponding engine or product.


## Compiled-in package licenses and bundled font

The following exact license texts were read from the local SwiftPM checkout files after confirming
that each checkout HEAD equals the revision pinned in `Package.resolved`, and that each working tree
is clean. Citations identify the upstream repository and exact revision/file; the text below is
verbatim from that file.

### FluidAudio 0.18.0 — Apache License 2.0
Source: https://github.com/FluidInference/FluidAudio/blob/e15287985625dbf544a343df679436789ffb03fb/LICENSE

                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

### argmax-oss-swift 1.1.1 — MIT License
Source: https://github.com/argmaxinc/argmax-oss-swift/blob/1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4/LICENSE

MIT License

Copyright (c) 2024 argmax, inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

### swift-argument-parser 1.8.2 — Apache License 2.0 with Runtime Library Exception
Source: https://github.com/apple/swift-argument-parser/blob/6a52f3251125d74daf04fcbd5e6f08a75d074382/LICENSE.txt

                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

    TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

    1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

    2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

    3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

    4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

    5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

    6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

    7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

    8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

    9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

    END OF TERMS AND CONDITIONS

    APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

    Copyright [yyyy] [name of copyright owner]

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.



## Runtime Library Exception to the Apache 2.0 License: ##


    As an exception, if you use this Software to compile your source code and
    portions of this Software are embedded into the binary product as a result,
    you may redistribute such product without providing attribution as would
    otherwise be required by Sections 4(a), 4(b) and 4(d) of the License.

### Plus Jakarta Sans font — SIL Open Font License 1.1
Source: `Sources/Zeus/Fonts/OFL.txt` in this project (SHA-256 at reconciliation: 995c7199cab65954f545996326755daee7b63cc6b42b06c13da1f9502ab08a99).

Copyright 2020 The Plus Jakarta Sans Project Authors (https://github.com/tokotype/PlusJakartaSans)

This Font Software is licensed under the SIL Open Font License, Version 1.1.
This license is copied below, and is also available with a FAQ at:
http://scripts.sil.org/OFL


-----------------------------------------------------------
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
-----------------------------------------------------------

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded, 
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply
to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical
writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining
a copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components,
in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole,
must be distributed entirely under this license, and must not be
distributed under any other license. The requirement for fonts to
remain under this license does not apply to any document created
using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are
not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
OTHER DEALINGS IN THE FONT SOFTWARE.

## OpenWhispr: local Whisper prompt-echo recovery

Source: https://github.com/mysticalsin/openwhispr
Pinned commit: e2f96ef01579f88a187a4179b357119208b50ab7
Upstream: https://github.com/OpenWhispr/openwhispr

The vocabulary-echo classifier and bounded local retry in
`Sources/ZeusCore/Dictation/WhisperPromptRecovery.swift` are adapted from
`src/utils/dictionaryEchoFilter.js` and the local Whisper recovery path in
`src/helpers/audioManager.js`. Zeus keeps the existing native engines and uses
a conservative retry policy; it does not bundle OpenWhispr's Electron application,
cloud service, fonts, or model weights.

MIT License

Copyright (c) 2024 OpenWhispr Team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## voice-glow: native assistant beam adaptation

Source: https://github.com/Jakubantalik/Libraries.dev/tree/main/packages/voice-glow
Package: voice-glow 0.2.1, by Jakub Antalik (MIT).

The native assistant beam adapts the package’s bottom-origin layered glow and
processing motion. Zeus supplies actual producer state and approved level data;
the React runtime, microphone helpers and the reference’s simulated speech are
not part of the native app. The user-supplied Voice Assistant Card timing reference
is https://transitions.dev/studio.html?id=c85AR0dBjUE.

MIT License

Copyright (c) 2026 Jakub Antalik

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Pointing interaction code (MIT)

Parts of the pointing interaction are adapted from an open-source project under the MIT License.

Copyright (c) 2026 Farza

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
