# First-run defaults

Owner rule (2026-11-11): what the owner asks for should be the default, so the first use of Zeus is already the
best experience. Exceptions only where a default would spend money, record people, or download without consent;
those ship as a ticked, visible choice in onboarding instead.

| Area | Default on a fresh install | Why / constraint |
|---|---|---|
| Voice | Ultron persona and Ultron voice effect on, intensity 60 % | Owner request. Best engine available automatically, never Samantha |
| Talk to Zeus | Fast tier race (Haiku, fast OpenAI model) with Sonnet deep follow-up | Owner request, first word target under 1.5 s |
| Instant commands | Rules then Jev; Jev active once a key exists | Money: the Jev monthly limit defaults to US$10 (also the ceiling) until the owner saves a different number; a saved limit is never overwritten, and Remove keeps it off |
| Pointing | Control+Option hold to talk, draw while held | Owner decisions 2026-11-10 |
| Language packs | English, French, Spanish, Portuguese ticked in onboarding, installed after setup | Download consent = visible ticked step |
| Scribe speakers | Speaker recognition model ticked in onboarding with the language packs; names from call window on when Accessibility already granted | Download consent; no permission prompt |
| Scribe saved voices | Off; per person, opt-in | Biometric data of other people |
| Scribe "When a meeting starts" (`scribe.autoStart`, Settings > Features > Scribe) | "Ask me" (choices: Off, Ask me, Start automatically) | Recording people without asking needs the owner's explicit choice. "Start automatically" shows a 5 second countdown with Cancel and starts only when Microphone is already allowed and after a one-time consent (asked on the first automatic start, stored as a timestamp); the detector never triggers a permission prompt, it asks instead. Call end (mic released 8 s, or call window gone) offers stop and save with Keep recording; a next meeting while recording asks before switching |
| Record | Main display selected | Owner request |
| Dictation sound | Crystal: a soft two-note glass chime rising on start and falling on stop, a low blip on cancel or error, at volume 70. Changeable in Settings > Dictation (Crystal, Soft click, Glass, Pop, Airy, None). Start plays on key down before the mic opens; stop plays on release | Owner request. Original sounds made by scripts/gen-dictation-sounds.py, no copied sounds |
| Dictation speed | Speech model loads on key down and stays loaded 10 minutes after last use; audio is transcribed in chunks while the key is held | Owner request, target under 300 ms from release to text |

Tests: `Tests/ZeusCoreTests/FirstRunDefaultsTests.swift` proves each row above (except Jev, owned by another branch) against a
fresh `UserDefaults` suite. The Ultron effect default (on, 60 %) is also proved on the app side in `UltronVoiceEffectTests`.
Pointing now has a separate "Draw while held" setting (`pointing.drawWhileHeld`, on); the screenshot upload
(`pointing.sendScreenshot`) stays off and needs Screen Recording already granted. Call-window names
(`scribe.callWindowNames`) is a policy only so far: `ScribeCallWindowNamesPolicy` says on-by-default and never without
Accessibility; the reader of the call window is not built yet.
