# Per-app equaliser and volume: plan and design

Written 13 November 2026 on `codex/island-20261113` at `47566d1`. Third wave after `docs/NOTCH-MUSIC-PLAN.md` and
`docs/NOTCH-SURFACE-PLAN.md`, both assumed merged first and not redone here. Same rules: pure rules in ZeusCore with
tests first, `docs/DESIGN-DIRECTION.md` for anything visible, nothing accepted until the named tests run on macOS and
the result is heard on a Mac. Public interfaces only: the Core Audio process tap API that Zeus already uses for its
two listen-only taps. Off by default; nothing is asked until the owner turns it on.

| Ticket | Gap | Today | After |
| --- | --- | --- | --- |
| B0 | Shared types | None | One small Core file of values and the `@MainActor` control protocol, so B1a, B1b and B2a compile apart |
| B1a | Filter maths | Only `UltronAudioChain` shapes Zeus's own voice | Pure biquad design, a cascade kernel, gain staging, a soft limiter and smoothing, tested with sines and impulses |
| B1b | Settings model | None | Ten bands, presets, per-app settings keyed by bundle id, a versioned codec that never loses data |
| B2a | Engine rules | None | Who may be shaped, grouping, pauses, format and stream checks, a lifecycle reducer, back-off, watchdog |
| B2b | Tap engine | Two listen-only global taps | One muted-when-tapped tap per shaped app, rendered to the current output in the same callback |
| B3 | Consent | The spectrum records `allowed` after any open | The owner's switch is the only way to the prompt; a probe proves sound arrives before anything is muted |
| B4 | Settings surface | None | A "Per-app sound" card on the Sounds page: apps, bands, presets, volume, bypass, a state line |

Order: B0 first. Then B1a, B1b and B2a in parallel, each branched from B0. Then B2b and B4 in parallel. B3 last,
because it edits files from B2a, B2b and B4. The file table near the end lists every shared file.

## Open source checked first

Licences were read from each LICENSE file in the research verification of 13 November 2026.

| Need | Project | Licence | Use |
| --- | --- | --- | --- |
| Tap build and teardown, rebuild back-off, Swift 6 `@Sendable` IOProc block | pantafive/fader | MIT | Base to adapt for `AppShapingTap`; notice in both notice files. Its macOS 15 floor and atomics are not taken |
| Process object and PID readers | insidegui/AudioCap | BSD-2-Clause | Base to adapt for the public process-list readers only. Its private permission check is not used |
| Coefficient bank swap, limiter idea | Sakuleta/tapmix | MIT | Technique only: very young project on tools version 5.10 |
| Lock-free handoff below macOS 15 | ZephyrSai/EQBar | Apache-2.0 | Technique only: Zeus keeps its own try-lock mailbox (precedent `ScribeSampleRing`) |
| Per-app volume and EQ, input stream usage, Bluetooth notes | ronitsingh10/FineTune | GPL-3.0 | Technique only. No code read into Zeus |
| Mixer apps on taps | PabloJuGo/OpenMixer, erdmncdr/Mikser, myUdav4iik/TapEQ, vorssaint/vorssaint-utils | GPL-3.0 | Technique only |
| Virtual output driver | kyleneideck/BackgroundMusic (GPL-2.0), bitgapp/eqMac (Apache-2.0), Torteous44/radioform (GPL-3.0) | as listed | Technique only; the driver approach is out of scope |
| 5-band EQ on taps | chomey/turnthatdown | MIT per its page, no LICENSE file | Not copied until a licence file exists |
| Filter formulas | Audio EQ Cookbook (R. Bristow-Johnson, W3C note) | public formulas | Peaking and shelf coefficients |
| API facts | CoreAudio headers in the local macOS 27.2 SDK | n/a | `AudioHardwareTapping.h`, `CATapDescription.h`, `AudioHardware.h` |

No new package dependency. `Package.swift:6` sets macOS 14.2, so `Synchronization.Atomic` (macOS 15) is out. The
mailbox uses an `os_unfair_lock` try-lock and counters use `OSAtomicAdd64Barrier`, as `ScribeSampleRing` does
(`Sources/ZeusCore/Scribe/ScribeLiveLogic.swift:1059-1078`, try-lock `:1099`, counter `:1125-1127`). Copied MIT or BSD
code keeps its notice in `NOTICES.md` and `Resources/NOTICES.txt` (they have diverged; update both).

Out of scope, each waiting on an owner decision:

- A permission preflight: macOS has no public call to read or request System Audio Recording. Zeus infers it (B3).
- Proving which app a shared web engine helper plays for needs a private responsibility call. Shared WebKit helpers
  are never shaped, so Safari audio is not shaped in this wave.
- A virtual output driver: public, but an admin install and an audio service restart. A different product shape.
- Per-tab shaping in a browser: audio would cross the pull-only bridge and its 1 MB native-messaging limit.
- `CATapDescription.bundleIDs` and `isProcessRestoreEnabled` (public, macOS 26 only): later, behind `#available`.

## Privacy and consent

- Off by default: `audio.equaliser` joins the `opt_in` tuple in `scripts/gen-settings-catalog.py` (`:238` today).
- The only path to the System Audio Recording prompt is the owner turning the switch on, or pressing "Try again".
  Never at launch, never from the permission sweep or onboarding, never from a test.
- A stored `allowed` never permits muting. `AudioSpectrumService` writes `allowed` after any `open()` that does not
  throw (`Sources/Zeus/Audio/AudioSpectrumService.swift:96-109`), and tap calls return `noErr` without a grant.
- The prompt must describe this use: B3 extends `NSAudioCaptureUsageDescription` (`Resources/Info.plist:29-30`).
- Audio never leaves the render callback. The store holds bundle ids, names, gains and volumes only.
- Tests never create a tap or a live monitor. A lint fails if `Tests/` names `AudioHardwareCreateProcessTap`,
  `CATapDescription`, `LiveShapingTapFactory` or `AudioProcessMonitor(`.

## B0. Shared types

New file `Sources/ZeusCore/Audio/EqualiserTypes.swift`, `Sendable` values: `BiquadKind` (`peaking`, `lowShelf`,
`highShelf`); `EqualiserParameters` (ten gains, volume, bypass; no preamp, see B1a); `AppSoundSettings` (`bundleID`,
`displayName`, `gainsDB`, `volume`, `shapes`, `lastUsed`); `EqualiserExclusion` (`zeus`, `callApp`, `sharedEngine`,
`noBundleID`, `otherDevice`); `EqualiserPause`; `EqualiserStop`; `EqualiserRow`; `EqualiserStatus` (line, symbol,
rows) with `snapshotSample`. And `@MainActor public protocol EqualiserControlling: AnyObject` with `status`,
`setSwitch(_:)`, `update(_ settings:)`, `forget(bundleID:)` and `tryAgain()`.

Tests first (`Tests/ZeusCoreTests/EqualiserTypesTests.swift`): a `@MainActor` fake conforms and compiles, which guards
the isolation mismatch class seen in TYPE-012 (`qa/native-compile-regressions.md:63`).

## B1a. Filter maths

### Behaviour

- Each band is a second-order filter: a low shelf at the bottom, a high shelf at the top, peaking between. Gains run
  from minus 12 to plus 12 dB; a flat band is skipped, so flat costs nothing.
- Boosting cannot clip: a preamp lowers the signal by the largest boost, and a soft limiter catches what remains.
- Changes glide: band gains move at most 1.5 dB per buffer. The preamp is computed from the smoothed gains each buffer,
  so it moves with the boost. Preamp and volume ramp linearly inside each buffer; volume settles over 20 ms.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/Audio/EqualiserDSP.swift`:

| Name | Rule |
| --- | --- |
| `BiquadDesign.coefficients(kind:frequency:gainDB:q:sampleRate:)` | Cookbook formulas, `A = 10^(dB/40)`, `w0 = 2 pi f / fs`, `alpha = sin(w0) / (2Q)`, as `BiquadCoefficients` over `a0`. Identity for gain 0, frequency at or above 0.45 fs, or any non-finite input |
| `BiquadDesign.magnitudeDB(_:frequency:sampleRate:)` | The response at one frequency, for tests and the B4 curve |
| `BiquadCascade` | Transposed direct form II per channel, state preallocated, no gain staging |
| `GainStaging.preampDB(bandGainsDB:)`, `GainStaging.linear(volume:)` | Minus the largest positive gain; `volume^2`, exactly 0 at 0 and 1 at 1 |
| `SoftLimiter`, `ParameterSmoothing.step(current:target:maxStep:)` | Threshold minus 1 dBFS, instant attack, 50 ms release, output finite with magnitude at most 1; a step moves at most `maxStep` toward the target |
| `EqualiserMailbox` (final class, `@unchecked Sendable`) | Slots preallocated; the lock is an `UnsafeMutablePointer<os_unfair_lock>` allocated in `init`, as in `ScribeSampleRing` (a stored lock can move). `post(_:)` locks on main; `take(into:)` try-locks and returns false when busy, so the render keeps its last values. Internal `withLockHeldForTesting(_:)` |
| `EqualiserKernel` (final class, `@unchecked Sendable`) | `init(maxChannels:maxFrames:bandCount:)` allocates everything. `process(_:frames:channels:interleaved:sampleRate:)`: take, smooth, coefficients at most once per buffer, cascade, preamp, volume ramp, limiter. No allocation, no Foundation. Non-finite output resets state and writes silence for that buffer. `reset()` only at build, before `AudioDeviceStart` |
| `RenderScratch` (final class, `@unchecked Sendable`) | Owns the scratch pointers, so the `@Sendable` render block captures a class, not raw pointers, which Swift 6 rejects |

### Tests first (`Tests/ZeusCoreTests/EqualiserDSPTests.swift`)

1. Coefficients match reference values to 1e-9; `magnitudeDB` gives the gain at the centre and on shelf plateaus
   within 0.1 dB; gain 0, 0.45 fs and non-finite inputs give identity.
2. Cascade alone: an impulse of 0.25 through a flat cascade is unchanged; a 1 kHz sine through plus 6 dB rises 6 dB.
3. Full kernel, inputs below the limiter threshold, plus 6 dB at 1 kHz: 1 kHz minus 100 Hz is plus 6 dB within 0.2 dB,
   and the 1 kHz level equals the input within 0.2 dB (preamp minus 6, peak plus 6).
4. A full-scale sine with every band at plus 12 dB never exceeds 1.0; a NaN mid-buffer gives one silent buffer.
5. A band jump from 0 to plus 12 dB takes 8 buffers, no step above 1.5 dB, and broadband RMS never falls more than
   1.5 dB from one buffer to the next.
6. Volume 0 gives exact zeros once the 20 ms ramp completes; the ramp is monotonic at 44.1, 48 and 96 kHz.
7. Mono, stereo, interleaved and planar give the same result per channel. Inside `withLockHeldForTesting`,
   `take(into:)` returns false and the kernel keeps its previous values.
8. `EqualiserKernelAllocationTests`: 1000 buffers leave `malloc_zone_statistics` `blocks_in_use` unchanged; enabled
   only with `ZEUS_ALLOC_CHECK=1` and run alone with `--no-parallel`, so other suites cannot skew it.

## B1b. Settings model and presets

### Behaviour

- Ten bands at 31.5, 63, 125, 250, 500, 1k, 2k, 4k, 8k and 16k Hz (ISO 266 octave centres).
- Presets: Flat, More bass, Less bass, More treble, Less treble, Clear voice, Fuller sound, Small speakers. A moved
  band shows "Custom". Each app has its own gains, a volume from 0 to 100 percent and a "Shape this app" switch.
- An app at flat and 100 percent, or with the switch off, is neutral and never tapped.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/Audio/EqualiserModel.swift`:

- `EqualiserBand` (frequency, `BiquadKind`, q) and `.standard` (Q 1.41 peaks, 0.71 shelves).
- `EqualiserGain.range`, `.step` (0.5), `.clamp(_:)`, `.spokenValue(_:)` (`spokenValue(3) == "plus 3 decibels"`).
- `EqualiserPreset` with `title`, `gains`, `matching(_:)` (nil is Custom). `AppSoundSettings.isNeutral`, `clamped()`.
- `AppSoundBook`: version 1, by bundle id, at most 64 apps. A 65th drops the oldest neutral entry; with none neutral,
  `add` returns `.full` and the card says "Too many apps saved. Forget one to add another."
- `AppSoundBook.decode(_:) -> (book:, failed:)`: bad JSON, a wrong gain count or an unknown version give an empty book
  and `failed` true; nil data is empty and not failed. `encode()`, `parameters(for:)`.
- `EqualiserListRules.rows(groups:book:exclusions:)`: playing first, then saved, by name, with exclusion labels.

Stored under the raw key `equaliser.apps`, like `audio.capturePermission` (`AudioSpectrumService.swift:13`). On a
failed decode the controller copies the raw data to `equaliser.apps.unreadable` before any save and never overwrites
that copy automatically.

### Tests first (`Tests/ZeusCoreTests/EqualiserModelTests.swift`)

Band table; presets in range; `matching` finds each preset and returns nil after one move; clamping; `spokenValue`
for plus, minus and 0; neutral cases; round trip; corrupt, short and future-version data fail; the cap drops the
oldest neutral entry and refuses when none is neutral; list ordering and labels; every preset title and label is free
of U+2014 and U+2013, since the em dash lint covers only `Sources/Zeus` (`test_source_lint.py:126-131`).

## B2a. Engine rules

### Behaviour

- Helper processes join their app (a browser's renderer and audio helpers are one entry).
- Never tapped: Zeus, call apps, shared WebKit helpers (`com.apple.WebKit.*` carry audio for every web view, not only
  Safari), processes with no bundle id, a group playing to another device.
- All taps are destroyed while a call app records, while Zeus records or captions system sound, while another Zeus
  holds the claim, during sleep, and while the output is unsupported.
- A tap exists only while its app plays and is not neutral: removed 30 s after output stops, at once on quit.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/Audio/EqualiserPolicy.swift` (`AudioProcessFacts`: object id, pid, bundle id, running
output, running input or nil when unreadable, devices):

| Name | Rule |
| --- | --- |
| `EqualiserPolicy.groups(_:runningAppBundleIDs:ownPID:)` | The longest running-app bundle id equal to or a dotted ancestor of the process bundle id. Not the WebKit to Safari mapping of call detection (`ScribeLiveLogic.swift:390-391`), right for reading and wrong for muting |
| `EqualiserPolicy.exclusion(for:ownBundleID:)` | `callApp` from `ScribeCallDetection.identify` (`:446`); `sharedEngine` for `com.apple.WebKit.*` |
| `EqualiserPolicy.callRecording(_:ownPID:)` | Input running, `pid != ownPID` and `MicConflict.counts(bundleID:pid:ownPID:)` (`Sources/ZeusCore/Intent/WakePhrase.swift:131-139`), the wake word's rule |
| `EqualiserPolicy.unreadableCounts(firstRead:reRead:pidAlive:)` | True only if still unreadable 250 ms later with the pid alive. Scribe treats `.unreadable` as an incomplete scan (`ScribeLiveLogic.swift:715`), not as recording |
| `EqualiserPolicy.zeusCaptures(scribe:polyglotActive:recordlySystemAudio:)` | True for `ScribePhase` `.starting`, `.recording`, `.ending` (`ScribeSession.swift:5`); `ScribeController.isRecording` misses `.starting` (`:445-450`) |
| `EqualiserPolicy.pauseReason(callRecording:zeusCaptures:otherShaper:asleep:format:)` | The `EqualiserPause`, or nil |
| `EqualiserFormat.verdict(tap:output:outputIsAggregate:)` | Float32 linear PCM, equal rates, an output channel, an output that is not an aggregate or multi-output device; else `unsupported(reason)` |
| `EqualiserRouting.channelMap(tapChannels:outputChannels:stereoPair:)` | Stereo to the device's pair; a mono device gets the average; other channels silence |
| `EqualiserRouting.tapStreamIndex(deviceInputStreams:aggregateInputStreams:tapStreams:)` | The tap's streams follow the sub-device's; nil when the counts do not add up |
| `ZeusAudioDevices.isOwnAggregate(uid:name:)` | UID prefix `app.zeus.eq.`, or "Zeus spectrum" and "Zeus Scribe" (`SystemAudioTap.swift:44`, `ScribeLiveCapture.swift:630`) |

New file `Sources/ZeusCore/Audio/EqualiserLifecycle.swift`:

| Name | Rule |
| --- | --- |
| `State` | `off`, `waitingForSound`, `probing(app, attempt)`, `running(apps)`, `paused(EqualiserPause)`, `stopped(EqualiserStop)`: `silentWhilePlaying(app)`, `repeatedFailures(app)`, `startFailed(status)` |
| `Event` | `switchedOn(personAsked:)`, `switchedOff`, `probeResult(app, verdict, seconds)`, `processesChanged`, `outputChanged`, `formatChanged`, `deviceGone`, `willSleep`, `didWake`, `callRecordingChanged`, `zeusCaptureChanged`, `claimLost`, `heartbeatMissed(app)`, `zerosWhilePlaying(app)`, `buildFailed(app, status)`, `idleExpired(app)`, `helperJoined(app)`, `retargetFailed(app)`, `settingsChanged` |
| `Effect` | `probe(app, maxSeconds)`, `buildTap(app)`, `retarget(app)`, `destroyTap(app)`, `destroyAll`, `scheduleRebuild(app, after:)`, `startWatchdog`, `stopWatchdog`, `recordAllowed`, `post(app, EqualiserParameters)` |
| `reduce(_:_:) -> (State, [Effect])` | Every pause, stop, sleep, `outputChanged`, `formatChanged` and `deviceGone` emits `destroyAll` first; a rebuild follows the new format verdict |
| `RebuildBackoff` | 0.5, 1, 2 and 4 s; a fifth failure inside 60 s stops that app |
| `EqualiserWatchdog.missed(lastBeatCount:currentCount:elapsed:appPlaying:)` | No callback for 2 s while the app plays |
| `ZeroWatch.verdict(zeroFrames:sampleRate:playing:muted:)` | 2 s of exact zeros under a muted tap while playing is a stall: `destroyTap(app)` first, so the app is audible, then `probe` |
| `EqualiserStatusText.line(for:)` | The state line copy (B3 Design) |

### Tests first (`Tests/ZeusCoreTests/EqualiserPolicyTests.swift`, `EqualiserLifecycleTests.swift`)

Helper grouping; a WebKit helper is `sharedEngine`, never Safari; own pid and bundle id excluded; every call app
excluded; another device excluded; own pid recording and a non-call recorder never pause; one transient unreadable
gives no `destroyAll`; Scribe `.starting`, Polyglot and Recordly system audio each pause with `destroyAll` first;
`outputChanged`, `formatChanged` and `deviceGone` give `effects[0] == .destroyAll`; format verdicts for Int16, a rate
mismatch, no channels and an aggregate output; channel maps for 1, 2 and 6; stream index for 0, 1 and 2 device inputs
and a mismatch; own-aggregate names and UIDs; neutral apps never get `buildTap`; back-off and the fifth-failure stop;
watchdog around 2 s and silent while not playing; zeros under a muted tap give `destroyTap` before any other effect;
idle expiry; quit; `helperJoined` gives `retarget`, `retargetFailed` a rebuild; off from every state gives `off` with
`destroyAll`; every status line is free of U+2014 and U+2013.

## B2b. Tap engine

### Behaviour

| Topic | Behaviour |
| --- | --- |
| Shape | Per shaped app: one private tap of its processes (`CATapDescription(stereoMixdownOfProcesses:)`, `isPrivate`, `.mutedWhenTapped`); one private aggregate (UID `app.zeus.eq.<uuid>`, name "Zeus EQ <app>") whose main and only sub-device is the current default output; one IOProc on a non-nil serial queue (a nil queue fails silently on macOS 26). Added latency is about one IO buffer (512 frames at 48 kHz is about 10.7 ms). Tap drift compensation off |
| Input streams | After `AudioDeviceCreateIOProcIDWithBlock`, before `AudioDeviceStart`: set `mStreamIsOn = 0` in `kAudioDevicePropertyIOProcStreamUsage` (input scope) for every stream except the tap's, so a headset microphone is never opened (no call profile, no microphone indicator). The index comes from `tapStreamIndex`; the render reads only that buffer. A failed read or write, or a nil index, destroys everything built and backs off |
| Output | Follows `kAudioHardwarePropertyDefaultOutputDevice`, not the system output the listen-only taps read (`SystemAudioTap.swift:118`). Output, rate or layout change and device removal (`kAudioDevicePropertyDeviceIsAlive`): every tap destroyed first, so the app plays unshaped on the new output, then rebuilt. Sleep, a pause, switch off and quit tear down; rebuild 2 s after wake |
| Helper joins | Write `kAudioTapPropertyDescription` on the live tap; rebuild only if the write fails or the next 2 s bring no callback |
| Single shaper | Before any build, an `flock` on `equaliser.lock` in Zeus's Application Support folder. Not taken: nothing built, "Paused: another copy of Zeus is shaping sound." The lock dies with the process |
| Own devices | `OutputDevices.ids()` (`Sources/Zeus/TopBar/OutputDevices.swift:12-17`) and `Microphones.deviceIDs()` (`Sources/Zeus/Dictation/Microphones.swift:33-39`) drop `isOwnAggregate`, so pickers never offer a Zeus aggregate |
| Crash | Startup sweep destroys any aggregate with UID prefix `app.zeus.eq.`. `equaliser.shapingSince` is written at the first build and removed on teardown; present at launch, the card says once: "Zeus stopped while shaping sound. If an app is silent, quit and reopen it." |
| Coexistence | The spectrum may draw a shaped app twice (visual only). Scribe, Polyglot and Recordly system capture pause shaping: they exclude Zeus's own audio (`PolyglotAudio.swift:107-108`, `RecordlyCaptureEngine.swift:281-282`) and would lose the shaped sound |
| Idle | Switch off: no listeners. On with nothing to shape: listeners only. The 1 Hz watchdog runs only while a tap exists |

### Files

| File | Notes |
| --- | --- |
| `Sources/Zeus/Audio/Equaliser/AudioProcessMonitor.swift` | Listeners on the process list, per-process output and input, the default output's rate, layout, transport type and liveness. Installed from `nonisolated static` functions on serial queue `zeus.equaliser.monitor`, delivered by `DispatchQueue.main.async` and `MainActor.assumeIsolated`. Reads via `ScribeCoreAudio` (`ScribeCallWatcher.swift:9-46`), shaped like `inputReads` (`:163-181`) |
| `Sources/Zeus/Audio/Equaliser/AppShapingTap.swift` | Shaped and probe modes. Teardown: `AudioDeviceStop`, `AudioDeviceDestroyIOProcID`, `queue.sync {}`, destroy aggregate, destroy tap. `ScribeSystemTap` syncs last (`ScribeLiveCapture.swift:652-670`); here it comes before render state is freed. `SystemAudioTap.stop()` has no sync (`SystemAudioTap.swift:65-77`); do not copy it. `nonisolated static func makeRenderBlock(kernel:scratch:map:tapIndex:meter:)` never captures `self`; the meter counts callbacks and zero frames with `OSAtomicAdd64Barrier`. Scratch sized from the largest buffer; longer callbacks run in chunks |
| `Sources/Zeus/Audio/Equaliser/EqualiserController.swift` | `@MainActor @Observable`, conforms to `EqualiserControlling`, holds one lifecycle state and applies effects. `init` has no default factory or monitor; live ones come only from `AppDelegate`. Sleep and wake via `NSWorkspace` on `.main` (as `NotchController.swift:78`). Zeus capture via `withObservationTracking` on `ScribeController.phase`, `PolyglotController.isListening` and `.isStarting`, `RecordlyController.isRecording` with system audio on; no polling. `applicationWillTerminate` destroys every tap and releases the claim |
| Edits | One filter line each in `OutputDevices.swift` and `Microphones.swift`; `scripts/check-perf-budget.sh` gains `CPU_BUDGET` (default 1) |

### Fail-closed behaviour

| Failure | What happens |
| --- | --- |
| Tap, aggregate, IOProc, stream usage or start fails | Everything built so far destroyed; the app plays unshaped; back-off |
| Unsupported format or aggregate output | No muted tap; "Paused: this output is not supported." |
| Callback stops while the app plays | Tap destroyed, app unshaped, back-off rebuild |
| 2 s of exact zeros under a muted tap | Tap destroyed first, then a probe; muted again only after `heard` |
| Mailbox busy / non-finite sample | Last values kept / silence for one buffer, state reset |
| Process unreadable twice, pid alive | Pause with `destroyAll` |
| Store unreadable | Raw copy kept, empty book, nothing shaped, the card says saved settings could not be read |
| Claim not taken | Nothing built; paused line |
| Zeus killed | Private taps should die with the process (owner check); the marker shows the notice next launch |

### Hazards that apply

- Swift 6: a closure written inside a `@MainActor` type inherits its isolation and traps on the HAL thread. The IOProc
  block and every listener block are built in `nonisolated static` functions.
- Realtime: no allocation, no locks but the mailbox try-lock, no main-actor hops, no logging in the callback.
  `SampleRing` takes an `NSLock` per write (`Sources/ZeusCore/Audio/Spectrum.swift:117-124`); never use it here.
- The callback lint matches only `installTap` and recognition handlers (`qa/closed-loop/tests/test_source_lint.py:16-22`,
  `:96-103`). Added, each with a fail-first sample: `test_io_proc_blocks_only_in_audited_files` (`SystemAudioTap`,
  `ScribeLiveCapture`, `AppShapingTap`); `test_shaping_render_has_no_allocation_or_main_hops` over `makeRenderBlock`
  and `EqualiserKernel.process` with its helpers (no array literals, `append`, `Array(`, `String(`, `DispatchQueue`,
  `MainActor`, `print`, `NSLog`); `test_tests_never_create_a_tap` (the four names in Privacy).
- Info.plist lint: add `AudioHardwareCreateProcessTap` to the table at `test_source_lint.py:105-125`, mapped to
  `NSAudioCaptureUsageDescription`.
- No new window, so the capture-visibility registry (`ZeusWindowSharing.apply`, `Sources/Zeus/App/ZeusWindowSharing.swift:29`)
  is untouched; any later floating panel must register there. The extension and the bridge are untouched.

### Tests first

`Tests/ZeusAppTests/EqualiserControllerTests.swift` (`@MainActor @Suite(..., .serialized)`) with a fake
`ShapingTapFactory` and monitor: a playing app gets a probe, then a tap; a call start destroys it first; Scribe
`.starting` pauses; sleep and wake; device removal; a held claim builds nothing; switch off leaves no tap or listener;
`shapingSince` present and absent; a failed decode keeps `equaliser.apps.unreadable`. A native-fixture entry in
`qa/feature-map.json`, otherwise CI compiles it and never runs it.

## B3. Consent and permission

### Behaviour

- Turning `audio.equaliser` on is the owner's request. The first time a non-excluded app plays, Zeus probes it.
- The probe is a listen-only tap (`.unmuted`, device inputs off as in B2b, output untouched). Nothing is muted, so a
  refusal can never silence an app. It ends early on `heard`.
- Length: up to 30 s for the first probe after `notAsked`, since the owner may still be reading the prompt; else up to
  5 s. The first muted tap of each app in a launch follows a `heard` probe, even with `allowed` stored.
- Zeros give `inconclusive`, retried on the next play with no new prompt. Two probes in a row, each at least 5 s, that
  see only zeros while the app reports running output enter `stopped(silentWhilePlaying)`. Every app stays unmuted.
- `heard` writes `allowed` through `AudioSpectrumService.recordProvenAllowed()`. Zeus never writes `refused`. A
  `refused` from the spectrum shows the stopped line without probing until "Try again".
- No new entitlement: `Resources/Zeus.entitlements` already has `com.apple.security.device.audio-input`, no sandbox.
- `NSAudioCaptureUsageDescription` gains: "and, if you turn on per-app sound, to adjust the sound of the apps you
  choose. That sound is changed as it plays and never saved." The plist lint and the dash rule apply.

### Rules (ZeusCore, pure)

In `EqualiserLifecycle.swift`: `EqualiserConsent.verdict(nonZeroFrames:framesSeen:appPlaying:) -> ProbeVerdict`
(`heard`, `silent`, `inconclusive`); `EqualiserConsent.probeSeconds(permission:)` (30 or 5);
`EqualiserConsent.stopsAfter(_:)` (two silent, each at least 5 s, while playing). `SpectrumGate.decision`
(`Spectrum.swift:165-171`) decides only whether a probe may start, never whether to mute.

App side: an `audio.equaliser` case beside `case AudioSpectrumService.liveKey` in `wireSettingsCatalog`
(`Sources/Zeus/App/AppDelegate.swift:870`, `:881` today); `EqualiserController.tryAgain()`;
`AudioSpectrumService.recordProvenAllowed()`; the System Settings link reuses `openSystemSettings()`
(`AudioSpectrumService.swift:69-71`); the usage string in `Resources/Info.plist`.

### Design

State line copy, one line, always a word with a symbol, never colour alone:

- "Off. No app is tapped." / "On. Play something in an app to finish setting up." / "Shaping 2 apps." /
  "On. Nothing to shape right now."
- "Paused while a call app uses the microphone." / "Paused while Zeus records or captions this Mac's sound." /
  "Paused: this output is not supported." / "Paused: another copy of Zeus is shaping sound."
- Stopped: "Zeus hears nothing from Music while it plays. If System Audio Recording is off for Zeus, turn it on. If you
  just turned it on, quit and reopen Zeus. Then press Try again." Buttons "Open System Settings" and "Try again".
- Stopped: "Stopped shaping Spotify after repeated errors. It plays normally." with "Try again".

### Tests first (`Tests/ZeusCoreTests/EqualiserConsentTests.swift`)

No probe without a person's request; a stored `allowed` still emits `probe` before `buildTap`; a recorded refusal
waits for Try again; the first probe after `notAsked` is 30 s; verdicts; one silent probe is inconclusive, two stop,
a short silent probe does not count; no muted `buildTap` follows a silent probe; `recordAllowed` only after `heard`;
no effect writes a refusal; switching off during a probe destroys the probe tap.

## B4. Settings surface

### Behaviour

- A "Per-app sound" card in `Sources/Zeus/Settings/GSEqualiserCard.swift`, placed in `SoundsPage`
  (`GlanceSettingsPages.swift:530`) after `GSCard("Voice cues")` (`:573`) and outside the `.disabled(!soundsOn)`
  modifier that wraps it (`:582`): shaping does not depend on Zeus's own sounds.
- Top row: the switch "Shape sound per app" and the state line. Then `EqualiserListRules.rows`: icon, name, a
  "Playing" tag, "Shape this app" (off truly removes the tap), volume 0 to 100 percent, a disclosure.
- Opened row: a preset menu (with "Custom"), ten band sliders labelled 31.5 to 16k, the response curve, "Reset to
  flat", "Forget this app". Changes apply live through `update(_:)`; saving is debounced to 300 ms.
- Excluded apps that play are greyed with a reason: "Call app: never shaped", "Shared web audio: never shaped",
  "Plays to another output".

### Design

- `GSCard`, `GSRow`, `GSToggleRow` as on the Sounds page; volume uses `OBTickSlider` unchanged.
- Bands use a new `GSBandSlider` in the card file. `OBTickSlider` is horizontal, fills from the leading edge, draws a
  dot per step and speaks "percent" (`Sources/Zeus/Onboarding/OnboardingSteps.swift:619-660`), so it cannot serve a
  bipolar control. `GSBandSlider`: vertical, fill from the 0 dB centre, ticks at minus 12, minus 6, 0, plus 6 and
  plus 12, snaps to 0.5 dB, adjusts one step, speaks `EqualiserGain.spokenValue` ("125 hertz band", "plus 3
  decibels"). The onboarding file is not edited.
- The curve is drawn from `BiquadDesign.magnitudeDB` at 64 log-spaced points, never from audio, and is hidden from
  accessibility. Reduce Motion: the curve and the disclosure change without animation.
- Snapshots: when `TopBarStyle.isSnapshot`, the card shows `EqualiserStatus.snapshotSample` and never starts the
  controller (as `AudioSpectrumService.swift:84`). No string carries an em dash (`test_source_lint.py:126`); the card
  is placed on a page (`:313`).

### Tests first

`Tests/ZeusAppTests/EqualiserCardTests.swift` against a `@MainActor` fake `EqualiserControlling`: the switch calls
`setSwitch`; a band move calls `update` with a clamped gain; Forget calls `forget`; the snapshot never touches the
controller. Its own native-fixture entry in `qa/feature-map.json`. Ordering and labels are pure, in B1b.

## Settings and catalog

One new row in `scripts/gen-settings-catalog.py`, section `sounds`, group "Per-app sound", after the `audio.spectrum`
rows: `audio.equaliser`, toggle, default false, state `custom`, label "Shape sound per app", note "Taps only the apps
you shape, with System Audio Recording. Off removes every tap." Added to the `opt_in` tuple. `SettingsCatalog.swift`
and `docs/settings-inventory.md` are regenerated, never edited by hand; `scripts/check-settings-catalog.sh` must pass.
The music plan adds rows to the same generator, so B4 rebases onto it. Raw keys, not catalog rows: `equaliser.apps`,
`equaliser.apps.unreadable`, `equaliser.shapingSince`.

## Parallel build and file sets

| Ticket | Worktree | Files | Parallel with | After |
| --- | --- | --- | --- | --- |
| B0 | `codex/eq-types-YYYYMMDD` | `EqualiserTypes.swift`, its test, `qa/regressions.json` | none | base |
| B1a | `codex/eq-dsp-YYYYMMDD` | `EqualiserDSP.swift`, its tests, `qa/regressions.json` | B1b, B2a | B0 |
| B1b | `codex/eq-model-YYYYMMDD` | `EqualiserModel.swift`, its test, `qa/regressions.json` | B1a, B2a | B0 |
| B2a | `codex/eq-rules-YYYYMMDD` | `EqualiserPolicy.swift`, `EqualiserLifecycle.swift`, two tests, `docs/STATE-MACHINES.md`, `qa/regressions.json` | B1a, B1b | B0 |
| B2b | `codex/eq-engine-YYYYMMDD` | `Sources/Zeus/Audio/Equaliser/*`, `OutputDevices.swift`, `Microphones.swift`, `AppDelegate.swift` (controller wiring), `test_source_lint.py`, `check-perf-budget.sh`, App test, notice files, `qa/feature-map.json`, `qa/regressions.json` | B4 | B1a, B1b, B2a |
| B4 | `codex/eq-card-YYYYMMDD` | `GSEqualiserCard.swift`, one line in `GlanceSettingsPages.swift`, the generator and its outputs, App test, `qa/feature-map.json`, `qa/regressions.json` | B2b | B1b, B2a |
| B3 | `codex/eq-consent-YYYYMMDD` | `EqualiserLifecycle.swift`, consent test, `AppDelegate.swift` (catalog case), `AudioSpectrumService.swift`, `Resources/Info.plist`, the controller and card, `docs/STATE-MACHINES.md` | none | B2b, B4 |

B2b and B4 build in parallel but share `qa/feature-map.json` and `qa/regressions.json`: B2b merges first, and B4
rebases its one feature-map entry. Every ticket claims REG ids in merge order; collisions are resolved with
`~/AI-Brain-build/zeus-merge-reg.py`. Core guards bind to `native-ZeusCoreTests`, the new lints to
`closed-loop-selftests`. Builds go in `~/AI-Brain-build/<name>-build`, never inside OneDrive.

## Measured limits the build must hold

- Added latency: one IO buffer beyond the device's own. Each build logs buffer size and rate; the owner checks lip sync.
- Render cost: one stereo app shaped at 48 kHz passes `PID=<pid> CPU_BUDGET=2 SECONDS_IDLE=60
  scripts/check-perf-budget.sh`. Always pass `PID=`: the default `pgrep` path (`check-perf-budget.sh:9`) is not ours.
- Idle, switch on, nothing shaped: `PID=<pid> SECONDS_IDLE=60 scripts/check-perf-budget.sh` passes 1 percent CPU and
  150 MB (`Sources/ZeusCore/Performance/PerformanceBudget.swift:5-6`); no IOProc, no timer. Switch off: no listeners.
- Stop latency: a call starting or the switch going off removes every tap within 250 ms of the listener firing.

## Verification for this wave

1. Tests are committed before the code and shown failing on the base (the build fails on the ticket's own new names).
2. `swift build --build-tests`, then `swift test --filter` per new suite, and
   `ZEUS_ALLOC_CHECK=1 swift test --no-parallel --filter EqualiserKernelAllocationTests` alone.
3. The whole `ZeusCoreTests` module on the branch and on the base, compared, with known failures recounted after the
   earlier waves merge.
4. `python3 -m unittest discover -s qa/closed-loop/tests -p 'test_*.py'`, the settings generator and its check,
   `./tools/check.sh` development mode from a worktree under `~/AI-Brain-build`.
5. A real compile on a Mac before any ticket is called done; agent sandboxes have not compiled Swift (TYPE-012).
6. An independent review of each diff, reading the realtime rules, stream usage and teardown order line by line.
7. Owed on a real Mac by the owner:
   - Audible: a bass boost in Music is heard; flat at 100 percent sounds like switch off; 50 percent volume is quieter
     for that app only; plus 12 dB never crackles; gaps between tracks cause no audible switch.
   - First run: the prompt comes only after the switch, while an app plays; Allow within 30 s starts shaping; refusing
     leaves every app audible. Revoking the permission mid-song: audible again within 3 s.
   - AirPods stay in stereo and no microphone indicator appears while shaping or probing. Switching to a Bluetooth
     headset mid-song and back: shaping follows within a second or two.
   - A call starting while music is shaped: shaping pauses, call audio is normal, music is not silent after.
   - Scribe, Polyglot captions and a Recordly recording of a shaped app: shaping pauses and the capture has the sound.
   - No "Zeus EQ" device in the output picker or microphone list. Two Zeus builds never double an app. A multi-output
     default gives the unsupported line, not five failed builds. A second browser tab with audio: no gap heard.
   - Sleep and wake, and unplugging the output, mid-song. Force quit while shaping: the sound returns at once (this
     decides whether taps stay private). The spectrum is not doubled. The measured limits, with numbers.

## Review notes

All 28 review findings were checked against the code and the research and accepted. Main changes: input stream usage;
a probe before every first muted tap; zeros unmute first; B0 so parallel tickets compile; preamp from smoothed gains;
the 30 s first probe and two-probe stop; the Zeus capture, call-rule, WebKit, own-aggregate and single-shaper rules;
a `@MainActor` protocol; destroy first on output change; the usage string; `CPU_BUDGET`; new owner checks.

Narrowed: a WebKit helper's parent needs a private call, so those helpers are always excluded. The allocation test
runs alone, since other suites allocate in parallel. Polyglot pauses shaping whenever it listens, as no source flag
was checked. The tap stream position comes from counts and fails closed on a mismatch until confirmed on device.
