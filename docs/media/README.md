# README captures

The README points at five GIF files. They are not in this repository. This directory's older stills and loops are earlier showcase assets. They are not those five shots, and this capture script does not read or replace them.

Record the five shots on a Mac, yourself, with `scripts/capture-readme-gifs.sh`. The script is opt-in. Until you pass `--record`, it only prints this list. It writes nowhere else than `docs/media/`, and only the file for the shot you named. It does not launch Zeus, does not install or replace an app, does not sign anything, and does not read or write system settings or the Keychain. It does not approve a permission prompt. If macOS asks for screen recording, that prompt is yours to answer.

`--record` runs only when `uname` is Darwin, and it refuses to run when `CI` or `GITHUB_ACTIONS` is set. Passing `--yes` skips the typed confirmation. It does not skip the macOS check.

## Shots

| Id | File | What to put in the rectangle |
| --- | --- | --- |
| `idle-top-bar` | `docs/media/idle-top-bar.gif` | The closed top bar only. The notch, or the pill on a Mac without one (`NotchController`). Do not open a page. The menu-bar icon may sit in frame. |
| `expanded-panel` | `docs/media/expanded-panel.gif` | The open top bar. Tab row and one page. Hover is the default open trigger (`notch.openTrigger`). |
| `murmur-dictation` | `docs/media/murmur-dictation.gif` | Murmure. Hold Right Command, the default dictation key, and show the live words and the orb. Focus a scratch document first: releasing the key types into the focused field. |
| `voice-orb` | `docs/media/voice-orb.gif` | The voice orb during a talk turn (`VoiceOrbStyle`). Right Option is the default second talk key; hold it for a quarter second before speaking. |
| `settings` | `docs/media/settings.gif` | The Settings window (`GlanceSettingsWindowController`), on Voice or Murmure. Leave other windows out of the rectangle. |

## How to record one

Open the Zeus you built (`scripts/bundle.sh` writes `build/Zeus.app`). Arrange the shot. Then, from the repository root, pass the rectangle in the coordinate system `screencapture -R` uses:

```sh
scripts/capture-readme-gifs.sh --record idle-top-bar --region 800,900,400,80
```

The script asks you to type `record` unless you also pass `--yes`. It then calls `/usr/sbin/screencapture` for a few frames of that rectangle. If `ffmpeg` is on `PATH`, it writes the GIF and deletes the frames. If `ffmpeg` is absent, it leaves `docs/media/<id>-frames/` and does not invent a GIF. Those frames are intermediate. Do not commit them.

`--replace` is required when the GIF, or that frames directory, already exists. `--duration` is seconds from 1 to 12. `--fps` is from 4 to 12. The defaults are 4 seconds and 8 frames per second. `screencapture` is slower than the requested rate, so the GIF's timing is the timing of the frames that were actually taken.

```sh
scripts/capture-readme-gifs.sh
scripts/capture-readme-gifs.sh --help
scripts/capture-readme-gifs.sh --record voice-orb --region 700,800,360,200 --duration 5 --fps 8
```

A GIF is committed only after a real capture. Do not draw a stand-in, and do not commit a single repeated frame as motion.
